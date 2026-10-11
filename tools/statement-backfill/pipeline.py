"""PDF statements → checked JSON → CSVs for `retire import`.

The stages (README.md):

1. Text: pdftotext -layout, with OCR for scanned pages.
2. Classify: what kind of statement, whose account, which period.
3. Extract: the model copies each page into JSON.
4. Check: balances must add up; pages that don't are asked again.
5. Assemble: accounts mapped and merged, transfers matched, months summed, CSVs written.

Every model reply is cached in the work folder, keyed by the PDF's hash, so a rerun only
asks the model about what changed. Amounts are `Decimal` throughout, never floats.
"""

from __future__ import annotations

import csv
import gc
import hashlib
import json
import re
import shutil
import subprocess
import sys
import time
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import date, timedelta
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Callable

PROMPTS = Path(__file__).parent / "prompts"

# A page with less text than this is treated as a scan.
SCAN_CHARS = 200
# The most text sent in one call; longer pages are cut (and reported).
MAX_PAGE_CHARS = 12_000
# Card and loan statements: how many pages are sent, joined.
DEBT_PAGES = 3

KINDS = {"bank", "broker", "card", "loan", "other"}
TRADE_TYPES = {
    "buy", "sell", "dividend", "interest", "fee", "tax", "deposit", "withdrawal",
    "transferIn", "transferOut", "split", "other",
}

# A model: takes chat messages, returns the reply's text.
Ask = Callable[[list[dict]], str]


@dataclass
class Config:
    statements: Path
    work: Path
    output: Path
    accounts: Path
    model: str
    retry_model: str | None = None
    limit: int | None = None
    only: list[str] = field(default_factory=list)
    ocr: bool = True
    retries: int = 1
    transfer_days: int = 4
    depot_transfer_days: int = 60
    show_replies: bool = False


def log(message: str = "") -> None:
    print(message, flush=True)


# MARK: - Model


class MLXModel:
    """A local model through mlx_lm, loaded once. Greedy decoding, so reruns agree."""

    def __init__(self, name: str, max_tokens: int = 8192):
        from mlx_lm import load

        log(f"Loading {name} …")
        started = time.time()
        self.name = name
        self.max_tokens = max_tokens
        self.model, self.tokenizer = load(name)
        log(f"Loaded in {time.time() - started:.0f}s")

    def __call__(self, messages: list[dict]) -> str:
        from mlx_lm import generate
        from mlx_lm.sample_utils import make_sampler

        prompt = self.tokenizer.apply_chat_template(messages, add_generation_prompt=True)
        started = time.time()
        reply = generate(self.model, self.tokenizer, prompt=prompt, max_tokens=self.max_tokens,
                         sampler=make_sampler(temp=0.0))
        seconds = time.time() - started
        tokens = len(self.tokenizer.encode(reply))
        speed = tokens / max(seconds, 0.01)
        log(f"      {len(prompt):,} tokens in, {tokens:,} out, {seconds:.1f}s ({speed:.0f} tok/s)")
        return reply


class LazyModel:
    """Loads the model on its first call, so a run where everything is cached loads nothing."""

    def __init__(self, name: str):
        self.name = name
        self.model: MLXModel | None = None

    def __call__(self, messages: list[dict]) -> str:
        if self.model is None:
            self.model = MLXModel(self.name)
        return self.model(messages)


def prompt(name: str, **values: object) -> str:
    """A prompt file with its {placeholders} filled in. Other braces (the JSON shapes) stay."""
    text = (PROMPTS / f"{name}.txt").read_text()
    for key, value in values.items():
        text = text.replace("{" + key + "}", "" if value is None else str(value))
    return text


# MARK: - Values


def amount(value: object, what: str) -> Decimal:
    """An amount the model wrote: a string (or number) like "-1234.56"."""
    if isinstance(value, bool) or value is None:
        raise ValueError(f"{what} is missing")
    text = str(value).strip().replace(" ", "").replace(" ", "")
    try:
        result = Decimal(text)
    except InvalidOperation:
        raise ValueError(f"{what} is not a plain decimal: {value!r}") from None
    if not result.is_finite():
        raise ValueError(f"{what} is not a plain decimal: {value!r}")
    return result


def optional_amount(value: object, what: str) -> Decimal | None:
    if value is None or (isinstance(value, str) and not value.strip()):
        return None
    return amount(value, what)


def day(value: object, what: str) -> date:
    try:
        return date.fromisoformat(str(value))
    except (TypeError, ValueError):
        raise ValueError(f"{what} is not a YYYY-MM-DD date: {value!r}") from None


def optional_day(value: object, what: str) -> date | None:
    return None if value in (None, "") else day(value, what)


def text(value: object) -> str:
    return "" if value is None else " ".join(str(value).split())


def money(value: Decimal | None) -> str:
    """An amount for the CSVs and the report: plain, with as many decimals as it has."""
    if value is None:
        return ""
    return format(value.normalize(), "f")


def account_key(number: object) -> str:
    """An account number to compare by: letters and digits, upper case, with hidden digits
    (**** or XXXX) as *."""
    key = re.sub(r"[^0-9A-Za-z*]", "", str(number or "")).upper()
    return re.sub(r"X{2,}", lambda run: "*" * len(run.group()), key)


def isin_key(isin: object) -> str:
    """An ISIN to compare by: letters and digits, upper case. Never masked, so XX stays."""
    return re.sub(r"[^0-9A-Za-z]", "", str(isin or "")).upper()


def parse_json(reply: str) -> dict:
    """The JSON object in a reply, without a code fence or text around it."""
    start, end = reply.find("{"), reply.rfind("}")
    if start < 0 or end < start:
        raise ValueError("the reply has no JSON object")
    body = reply[start:end + 1]
    # The prompts show the shape with // comments; a model sometimes copies them.
    body = re.sub(r'//[^\n"]*$', "", body, flags=re.MULTILINE)
    try:
        data = json.loads(body)
    except json.JSONDecodeError as error:
        raise ValueError(f"the JSON is invalid: {error}") from None
    if not isinstance(data, dict):
        raise ValueError("the reply is not a JSON object")
    return data


# MARK: - What the model returns, validated


def read_classification(data: dict) -> dict:
    kind = str(data.get("kind", "")).strip().lower()
    if kind not in KINDS:
        raise ValueError(f"kind must be one of {sorted(KINDS)}, not {data.get('kind')!r}")
    return {
        "kind": kind,
        "institution": text(data.get("institution")) or "unknown",
        "accountNumber": text(data.get("accountNumber")),
        "currency": text(data.get("currency")).upper() or None,
        "periodStart": optional_day(data.get("periodStart"), "periodStart"),
        "periodEnd": optional_day(data.get("periodEnd"), "periodEnd"),
        "statementDate": optional_day(data.get("statementDate"), "statementDate"),
    }


def read_bank_page(data: dict) -> dict:
    transactions = []
    for index, item in enumerate(data.get("transactions") or [], start=1):
        what = f"transaction {index}"
        if not isinstance(item, dict):
            raise ValueError(f"{what} is not an object")
        transactions.append({
            "date": day(item.get("date"), f"{what}'s date"),
            "description": text(item.get("description")),
            "amount": amount(item.get("amount"), f"{what}'s amount"),
            "balanceAfter": optional_amount(item.get("balanceAfter"), f"{what}'s balanceAfter"),
            "isInterest": item.get("isInterest") is True,
        })
    return {
        "openingBalance": optional_amount(data.get("openingBalance"), "openingBalance"),
        "closingBalance": optional_amount(data.get("closingBalance"), "closingBalance"),
        "transactions": transactions,
    }


def read_broker_page(data: dict) -> dict:
    transactions = []
    for index, item in enumerate(data.get("transactions") or [], start=1):
        what = f"transaction {index}"
        if not isinstance(item, dict):
            raise ValueError(f"{what} is not an object")
        kind = str(item.get("type", "")).strip()
        if kind not in TRADE_TYPES:
            kind = "other"
        quantity = optional_amount(item.get("quantity"), f"{what}'s quantity")
        transactions.append({
            "date": day(item.get("date"), f"{what}'s date"),
            "type": kind,
            "typeText": text(item.get("typeText")) or kind,
            "instrument": text(item.get("instrument")),
            "isin": isin_key(item.get("isin")) or None,
            "quantity": abs(quantity) if quantity is not None else None,
            "price": optional_amount(item.get("price"), f"{what}'s price"),
            "priceCurrency": text(item.get("priceCurrency")).upper() or None,
            "amount": optional_amount(item.get("amount"), f"{what}'s amount"),
            "fees": abs_or_none(optional_amount(item.get("fees"), f"{what}'s fees")),
            "tax": abs_or_none(optional_amount(item.get("tax"), f"{what}'s tax")),
            "ratio": optional_amount(item.get("ratio"), f"{what}'s ratio"),
            "description": text(item.get("description")),
        })
    holdings = []
    for index, item in enumerate(data.get("holdings") or [], start=1):
        what = f"holding {index}"
        if not isinstance(item, dict):
            raise ValueError(f"{what} is not an object")
        holdings.append({
            "instrument": text(item.get("instrument")),
            "isin": isin_key(item.get("isin")) or None,
            "quantity": amount(item.get("quantity"), f"{what}'s quantity"),
        })
    return {
        "transactions": transactions,
        "holdings": holdings,
        "cashOpening": optional_amount(data.get("cashOpening"), "cashOpening"),
        "cashClosing": optional_amount(data.get("cashClosing"), "cashClosing"),
    }


def read_debt(data: dict) -> dict:
    return {
        "statementDate": day(data.get("statementDate"), "statementDate"),
        "previousBalance": optional_amount(data.get("previousBalance"), "previousBalance"),
        "balanceOwed": amount(data.get("balanceOwed"), "balanceOwed"),
        "payments": optional_amount(data.get("payments"), "payments"),
        "interest": optional_amount(data.get("interest"), "interest"),
    }


def abs_or_none(value: Decimal | None) -> Decimal | None:
    return None if value is None else abs(value)


# MARK: - Cache


def encode(value: object) -> object:
    if isinstance(value, Decimal):
        return {"$decimal": str(value)}
    if isinstance(value, date):
        return {"$date": value.isoformat()}
    if isinstance(value, dict):
        return {key: encode(item) for key, item in value.items()}
    if isinstance(value, list):
        return [encode(item) for item in value]
    return value


def decode(value: object) -> object:
    if isinstance(value, dict):
        if set(value) == {"$decimal"}:
            return Decimal(value["$decimal"])
        if set(value) == {"$date"}:
            return date.fromisoformat(value["$date"])
        return {key: decode(item) for key, item in value.items()}
    if isinstance(value, list):
        return [decode(item) for item in value]
    return value


def save(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(encode(value), indent=2, ensure_ascii=False))


def load(path: Path) -> object | None:
    return decode(json.loads(path.read_text())) if path.exists() else None


# MARK: - Stage 1: text


def file_hash(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()[:16]


def pdf_pages(path: Path) -> list[str]:
    result = subprocess.run(["pdftotext", "-layout", str(path), "-"], capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"pdftotext failed: {result.stderr.strip()}")
    pages = result.stdout.split("\f")
    if pages and not pages[-1].strip():
        pages.pop()
    return pages


def read_text(path: Path, folder: Path, config: Config) -> dict:
    cached = load(folder / "text.json")
    if cached:
        return cached
    pages = pdf_pages(path)
    scanned = [i + 1 for i, page in enumerate(pages) if len(page.strip()) < SCAN_CHARS]
    ocr = False
    if scanned and config.ocr:
        if shutil.which("ocrmypdf"):
            log(f"    OCR: pages {scanned} have almost no text")
            target = folder / "ocr.pdf"
            subprocess.run(["ocrmypdf", "--skip-text", "--quiet", str(path), str(target)], check=True)
            pages = pdf_pages(target)
            ocr = True
            scanned = [i + 1 for i, page in enumerate(pages) if len(page.strip()) < SCAN_CHARS]
        else:
            log(f"    pages {scanned} have almost no text, and ocrmypdf isn't installed")
    result = {"file": str(path), "pages": pages, "ocr": ocr, "scanned": scanned}
    save(folder / "text.json", result)
    return result


# MARK: - Stages 2 and 3: classify and extract


def converse(ask: Ask, task: str, reader: Callable[[dict], dict], config: Config,
             history: list[dict] | None = None) -> tuple[dict, list[dict]]:
    """Asks the model `task` and reads its reply, asking once more if it can't be read.
    Returns what was read and the conversation, for a retry that follows up on it."""
    messages = history or [{"role": "system", "content": prompt("system")}, {"role": "user", "content": task}]
    for attempt in range(2):
        reply = ask(messages)
        if config.show_replies:
            log("      ── reply ──\n" + reply + "\n      ───────────")
        messages = messages + [{"role": "assistant", "content": reply}]
        try:
            return reader(parse_json(reply)), messages
        except ValueError as error:
            if attempt == 1:
                raise
            log(f"      unreadable reply ({error}), asking again")
            messages = messages + [{"role": "user", "content": prompt("unreadable", problem=error)}]
    raise AssertionError("unreachable")


def page_text(page: str) -> str:
    return page if len(page) <= MAX_PAGE_CHARS else page[:MAX_PAGE_CHARS] + "\n[… cut]"


def classify(ask: Ask, pages: list[str], folder: Path, config: Config) -> dict:
    cached = load(folder / "classify.json")
    if cached:
        return cached
    first = next((page for page in pages if page.strip()), "")
    result, _ = converse(ask, prompt("classify", page_text=page_text(first)), read_classification, config)
    save(folder / "classify.json", result)
    return result


def task_values(info: dict) -> dict:
    return {
        "institution": info["institution"],
        "account_number": info["accountNumber"] or "unknown",
        "currency": info["currency"] or "unknown",
        "period_start": info["periodStart"] or "unknown",
        "period_end": info["periodEnd"] or "unknown",
        "kind": "credit card" if info["kind"] == "card" else info["kind"],
    }


def extract_page(ask: Ask, kind: str, info: dict, pages: list[str], index: int,
                 config: Config) -> tuple[dict, list[dict]]:
    task = prompt(kind, page=index + 1, pages=len(pages), page_text=page_text(pages[index]), **task_values(info))
    reader = read_bank_page if kind == "bank" else read_broker_page
    return converse(ask, task, reader, config)


def extract(ask: Ask, info: dict, pages: list[str], folder: Path, config: Config) -> dict:
    """The statement's pages as the model read them, cached per page."""
    kind = info["kind"]
    if kind in ("card", "loan"):
        cached = load(folder / "debt.json")
        if cached:
            return cached
        joined = "\n\n".join(pages[:DEBT_PAGES])
        task = prompt("debt", page_text=page_text(joined), **task_values(info))
        result, _ = converse(ask, task, read_debt, config)
        save(folder / "debt.json", result)
        return result
    result = {"pages": []}
    for index, page in enumerate(pages):
        path = folder / f"page-{index + 1}.json"
        cached = load(path)
        if cached:
            data = cached["data"]
        elif not page.strip():
            data = read_bank_page({}) if kind == "bank" else read_broker_page({})
            save(path, {"data": data, "messages": []})
        else:
            log(f"    page {index + 1}/{len(pages)}")
            data, messages = extract_page(ask, kind, info, pages, index, config)
            save(path, {"data": data, "messages": messages})
        count = len(data["transactions"])
        holdings = len(data.get("holdings") or [])
        log(f"    page {index + 1}: {count} transactions" + (f", {holdings} holdings" if holdings else ""))
        result["pages"].append(data)
    return result


# MARK: - Stage 4: check


@dataclass
class Check:
    ok: bool
    message: str
    page: int | None = None  # the page to ask again, when one can be named
    reversed: bool = False   # the page lists transactions newest first


def check_bank(pages: list[dict]) -> Check:
    opening = next((p["openingBalance"] for p in pages if p["openingBalance"] is not None), None)
    closing = next((p["closingBalance"] for p in reversed(pages) if p["closingBalance"] is not None), None)
    if opening is None or closing is None:
        missing = "opening" if opening is None else "closing"
        return Check(False, f"no {missing} balance was read")
    printed = check_bank_order(pages, opening, closing, newest_first=False)
    if printed.ok:
        return printed
    newest_first = check_bank_order(pages, opening, closing, newest_first=True)
    return newest_first if newest_first.ok else printed


def check_bank_order(pages: list[dict], opening: Decimal, closing: Decimal, newest_first: bool) -> Check:
    lines = [(number, t) for number, page in enumerate(pages, start=1) for t in page["transactions"]]
    if newest_first:
        lines.reverse()
    running = opening
    for page, transaction in lines:
        before = running
        running += transaction["amount"]
        printed = transaction["balanceAfter"]
        if printed is not None and printed != running:
            return Check(False, f"page {page}, \"{transaction['description'][:40]}\" ({transaction['date']}): "
                         f"{money(before)} {'+' if transaction['amount'] >= 0 else '−'} "
                         f"{money(abs(transaction['amount']))} should give {money(running)}, "
                         f"but the page prints {money(printed)}", page=page, reversed=newest_first)
    total = sum((t["amount"] for _, t in lines), Decimal(0))
    if opening + total != closing:
        return Check(False, f"opening balance {money(opening)} + {len(lines)} transactions {money(total)} = "
                     f"{money(opening + total)}, but the closing balance is {money(closing)} "
                     f"({money(abs(closing - opening - total))} apart)", reversed=newest_first)
    return Check(True, f"opening {money(opening)} + {len(lines)} transactions = closing {money(closing)}",
                 reversed=newest_first)


def check_broker(pages: list[dict]) -> Check:
    opening = next((p["cashOpening"] for p in pages if p["cashOpening"] is not None), None)
    closing = next((p["cashClosing"] for p in reversed(pages) if p["cashClosing"] is not None), None)
    transactions = [t for p in pages for t in p["transactions"]]
    if opening is None or closing is None:
        return Check(True, f"{len(transactions)} transactions; no cash balances to check them against")
    total = sum((t["amount"] for t in transactions if t["amount"] is not None), Decimal(0))
    if opening + total != closing:
        return Check(False, f"cash {money(opening)} + {len(transactions)} transactions {money(total)} = "
                     f"{money(opening + total)}, but the closing cash is {money(closing)}")
    return Check(True, f"cash {money(opening)} + {len(transactions)} transactions = {money(closing)}")


def check(info: dict, extracted: dict) -> Check:
    if info["kind"] == "bank":
        return check_bank(extracted["pages"])
    if info["kind"] == "broker":
        return check_broker(extracted["pages"])
    return Check(True, f"owed {money(extracted['balanceOwed'])} on {extracted['statementDate']}")


def retry(ask: Ask, info: dict, pages: list[str], extracted: dict, result: Check, folder: Path,
          config: Config) -> tuple[dict, Check]:
    """Asks again about the pages a failed check points at, with the numbers that don't add up."""
    for _ in range(config.retries):
        targets = [result.page] if result.page else [i + 1 for i, p in enumerate(pages) if p.strip()]
        for number in targets:
            path = folder / f"page-{number}.json"
            cached = load(path) or {"messages": []}
            log(f"    asking again about page {number}")
            follow_up = None
            if cached["messages"]:
                follow_up = cached["messages"] + [{"role": "user", "content": prompt("retry", problem=result.message)}]
            try:
                if follow_up:
                    data, messages = converse(ask, "", read_page_reader(info), config, history=follow_up)
                else:
                    data, messages = extract_page(ask, info["kind"], info, pages, number - 1, config)
            except ValueError as error:
                log(f"    still unreadable: {error}")
                continue
            save(path, {"data": data, "messages": messages})
            extracted["pages"][number - 1] = data
        result = check(info, extracted)
        log(f"    {'✓' if result.ok else '✗'} {result.message}")
        if result.ok:
            break
    return extracted, result


def read_page_reader(info: dict) -> Callable[[dict], dict]:
    return read_bank_page if info["kind"] == "bank" else read_broker_page


# MARK: - Stages 1-4 for every PDF


def statement_files(config: Config) -> list[Path]:
    files = sorted(p for p in config.statements.rglob("*") if p.suffix.lower() == ".pdf")
    if config.only:
        files = [p for p in files if p.name in config.only]
    if config.limit:
        files = files[:config.limit]
    return files


def process(path: Path, ask: Ask, config: Config, model_name: str, retry_only: bool = False) -> None:
    folder = config.work / file_hash(path)
    status_path = folder / "status.json"
    status = load(status_path)
    # Done: it passed, or this pass's model already tried it. The first pass also leaves
    # statements the retry model already tried, so a rerun doesn't read them again.
    tried = {model_name} if retry_only else {model_name, config.retry_model}
    if status and (status["ok"] or status.get("model") in tried):
        log(f"    cached: {'✓' if status['ok'] else '✗'} {status['message']}")
        return
    if retry_only:
        # Start over with this model: drop what the other one read, its classification included.
        for page in folder.glob("page-*.json"):
            page.unlink()
        (folder / "debt.json").unlink(missing_ok=True)
        (folder / "classify.json").unlink(missing_ok=True)
    text_info = read_text(path, folder, config)
    pages = text_info["pages"]
    log(f"    {len(pages)} pages, {sum(len(p) for p in pages):,} characters" + (" (OCR)" if text_info["ocr"] else ""))
    info = classify(ask, pages, folder, config)
    log(f"    {info['kind']}: {info['institution']} {info['accountNumber'] or '(no account number)'}, "
        f"{info['periodStart'] or '?'} to {info['periodEnd'] or info['statementDate'] or '?'}")
    if info["kind"] == "other":
        save(status_path, {"ok": True, "message": "not a statement; skipped", "model": model_name, "skipped": True})
        return
    try:
        extracted = extract(ask, info, pages, folder, config)
    except ValueError as error:
        save(status_path, {"ok": False, "message": f"unreadable reply: {error}", "model": model_name})
        log(f"    ✗ unreadable reply: {error}")
        return
    result = check(info, extracted)
    log(f"    {'✓' if result.ok else '✗'} {result.message}")
    if not result.ok and info["kind"] in ("bank", "broker"):
        extracted, result = retry(ask, info, pages, extracted, result, folder, config)
    save(status_path, {"ok": result.ok, "message": result.message, "model": model_name,
                       "reversed": result.reversed})


def run(config: Config, ask: Ask | None = None, retry_ask: Ask | None = None) -> None:
    """Runs every stage. `ask` and `retry_ask` stand in for the models in tests."""
    if not shutil.which("pdftotext"):
        sys.exit("pdftotext isn't installed: brew install poppler")
    files = statement_files(config)
    log(f"{len(files)} PDFs in {config.statements}")
    model = ask or LazyModel(config.model)
    for number, path in enumerate(files, start=1):
        log(f"\n[{number}/{len(files)}] {path.relative_to(config.statements)}")
        try:
            process(path, model, config, config.model)
        except Exception as error:  # one bad PDF never stops the run
            log(f"    ✗ {type(error).__name__}: {error}")
    failed = [p for p in files if not (load(config.work / file_hash(p) / "status.json") or {}).get("ok")]
    if failed and (config.retry_model or retry_ask):
        log(f"\n{len(failed)} statements failed; trying them with {config.retry_model}")
        if ask is None:
            del model  # both models at once may not fit in memory
            gc.collect()
        second = retry_ask or LazyModel(config.retry_model)
        for number, path in enumerate(failed, start=1):
            log(f"\n[retry {number}/{len(failed)}] {path.relative_to(config.statements)}")
            try:
                process(path, second, config, config.retry_model or "retry", retry_only=True)
            except Exception as error:
                log(f"    ✗ {type(error).__name__}: {error}")
    log("\nAssembling")
    assemble(config, files)


# MARK: - Stage 5: assemble


@dataclass
class Statement:
    file: str
    kind: str
    institution: str
    number: str        # the account number as printed
    currency: str | None
    start: date | None
    end: date | None
    data: dict
    reversed: bool = False
    account: str | None = None  # the library account it maps to
    failed: bool = False        # its checks failed: its period is a hole in the account's history

    @property
    def source(self) -> str:
        return f"{self.institution} {self.number}"

    @property
    def last_day(self) -> date | None:
        return self.end or self.data.get("statementDate")


@dataclass
class Report:
    sections: dict[str, list[str]] = field(default_factory=lambda: defaultdict(list))

    def add(self, section: str, line: str) -> None:
        self.sections[section].append(line)


def load_statements(config: Config, files: list[Path], report: Report) -> list[Statement]:
    statements = []
    for path in files:
        folder = config.work / file_hash(path)
        status = load(folder / "status.json")
        name = str(path.relative_to(config.statements))
        if not status:
            report.add("Not read", f"{name}")
            continue
        if status.get("skipped"):
            continue
        info = load(folder / "classify.json")
        if not status["ok"]:
            report.add("Failed checks (left out)", f"{name}: {status['message']}")
            if info:
                statements.append(Statement(name, info["kind"], info["institution"], info["accountNumber"],
                                            info["currency"], info["periodStart"], info["periodEnd"], {},
                                            failed=True))
            continue
        if info["kind"] in ("card", "loan"):
            data = load(folder / "debt.json")
        else:
            data = {"pages": [load(page)["data"] for page in sorted(folder.glob("page-*.json"),
                                                                     key=lambda p: int(p.stem.split("-")[1]))]}
        statements.append(Statement(name, info["kind"], info["institution"], info["accountNumber"],
                                    info["currency"], info["periodStart"], info["periodEnd"], data,
                                    reversed=bool(status.get("reversed"))))
    return statements


def map_accounts(statements: list[Statement], config: Config, report: Report) -> list[Statement]:
    """Maps each statement's account number to a library account ID (accounts.json)."""
    mapping = {}
    if config.accounts.exists():
        mapping = {account_key(k): v for k, v in json.loads(config.accounts.read_text()).items()
                   if not k.startswith("_")}
    unknown: dict[tuple, int] = defaultdict(int)
    mapped = []
    for statement in statements:
        key = account_key(statement.number)
        target = mapping.get(key)
        shown = key.split("*")[-1]
        if target is None and "*" in key and len(shown) >= 4:
            # A masked number (**** 4242): match on the digits it shows.
            matches = {v for k, v in mapping.items() if k.endswith(shown)}
            if len(matches) == 1:
                target = matches.pop()
        if target is None:
            unknown[(statement.kind, statement.institution, statement.number or "(none)")] += 1
            continue
        statement.account = target
        mapped.append(statement)
    for (kind, institution, number), count in sorted(unknown.items()):
        report.add("Accounts not in accounts.json (left out)", f"{kind}: {institution} {number} ({count} statements)")
    return mapped


def by_source(statements: list[Statement]) -> dict[str, list[Statement]]:
    groups: dict[str, list[Statement]] = defaultdict(list)
    for statement in statements:
        groups[statement.source].append(statement)
    for group in groups.values():
        group.sort(key=lambda s: (s.start or s.last_day or date.min, s.file))
    return groups


def bank_lines(statement: Statement) -> list[dict]:
    lines = [t for page in statement.data["pages"] for t in page["transactions"]]
    return list(reversed(lines)) if statement.reversed else lines


def bank_ends(statement: Statement) -> tuple[Decimal, Decimal]:
    pages = statement.data["pages"]
    opening = next(p["openingBalance"] for p in pages if p["openingBalance"] is not None)
    closing = next(p["closingBalance"] for p in reversed(pages) if p["closingBalance"] is not None)
    return opening, closing


def month_ends(first: date, last: date) -> list[date]:
    ends = []
    year, month = first.year, first.month
    while True:
        following = date(year + (month == 12), month % 12 + 1, 1)
        end = following - timedelta(days=1)
        if end > last:
            return ends
        ends.append(end)
        year, month = following.year, following.month


@dataclass
class Movement:
    """A bank transaction or a broker's deposit or withdrawal, for matching transfers."""
    account: str
    source: str
    date: date
    amount: Decimal
    line: dict
    transfer: bool = False


def match_transfers(movements: list[Movement], days: int) -> int:
    """Marks pairs of opposite, equal amounts in two different statement accounts within `days`
    as transfers. Returns how many pairs."""
    incoming: dict[Decimal, list[Movement]] = defaultdict(list)
    for movement in movements:
        if movement.amount > 0:
            incoming[movement.amount].append(movement)
    pairs = 0
    for out in sorted((m for m in movements if m.amount < 0), key=lambda m: m.date):
        candidates = [m for m in incoming[-out.amount]
                      if not m.transfer and m.source != out.source and abs((m.date - out.date).days) <= days]
        if not candidates:
            continue
        best = min(candidates, key=lambda m: abs((m.date - out.date).days))
        out.transfer = best.transfer = True
        out.line["transfer"] = best.line["transfer"] = True
        pairs += 1
    return pairs


def assemble_banks(statements: list[Statement], report: Report) -> list[dict]:
    rows = []
    sources = by_source([s for s in statements if s.kind == "bank"])
    # Balance points and coverage per source account.
    points: dict[str, list[tuple[date, Decimal]]] = {}
    coverage: dict[str, list[tuple[date, date]]] = {}
    for source, group in sources.items():
        kept: list[Statement] = []
        for statement in group:
            if statement.start is None or statement.end is None:
                report.add("Statements without a period (left out)", f"{statement.file}")
                continue
            if kept and statement.start <= kept[-1].end:
                report.add("Overlapping statements (later one left out)", f"{statement.file} overlaps {kept[-1].file}")
                continue
            if kept and not statement.failed and not kept[-1].failed:
                previous = kept[-1]
                if statement.start > previous.end + timedelta(days=1):
                    report.add("Gaps (missing statements)", f"{source}: {previous.end + timedelta(days=1)} to "
                               f"{statement.start - timedelta(days=1)}")
                if bank_ends(statement)[0] != bank_ends(previous)[1]:
                    report.add("Balances that don't carry over", f"{source}: {previous.file} closes at "
                               f"{money(bank_ends(previous)[1])}, {statement.file} opens at "
                               f"{money(bank_ends(statement)[0])}")
            kept.append(statement)
        sources[source] = kept
        series: list[tuple[date, Decimal]] = []
        spans = []
        for statement in kept:
            if statement.failed:
                continue
            opening, closing = bank_ends(statement)
            series.append((statement.start - timedelta(days=1), opening))
            running = opening
            for line in sorted(bank_lines(statement), key=lambda t: t["date"]):
                running += line["amount"]
                series.append((line["date"], running))
            series.append((statement.end, closing))
            spans.append((statement.start - timedelta(days=1), statement.end))
        points[source] = series
        coverage[source] = spans

    def balance(source: str, on: date) -> Decimal | None:
        if not any(start <= on <= end for start, end in coverage[source]):
            return None
        value = None
        for point_date, point_value in points[source]:
            if point_date > on:
                break
            value = point_value
        return value

    accounts: dict[str, list[str]] = defaultdict(list)
    for source, group in sources.items():
        if group:
            accounts[group[0].account].append(source)
    for account, members in sorted(accounts.items()):
        first = min(sources[m][0].start for m in members)
        last = max(sources[m][-1].end for m in members)
        lines = [line for m in members for s in sources[m] if not s.failed for line in bank_lines(s)]
        for m in members:
            if sources[m][-1].failed:
                continue
            closing = bank_ends(sources[m][-1])[1]
            if sources[m][-1].end < last and closing != 0:
                report.add("Merged accounts that stop with money in them",
                           f"{m} ({account}): {money(closing)} on {sources[m][-1].end}")
        previous_end = None
        for end in month_ends(first, last):
            active = [m for m in members
                      if sources[m][0].start - timedelta(days=1) <= end <= sources[m][-1].end]
            if not active:
                previous_end = None
                continue
            values = [balance(m, end) for m in active]
            if any(v is None for v in values):
                report.add("Month ends left out (a statement is missing)", f"{account}: {end}")
                previous_end = None
                continue
            row = {"date": end, "account": account, "balance": sum(values, Decimal(0)),
                   "moneyIn": None, "moneyOut": None, "interest": None}
            if previous_end is not None:
                month = [t for t in lines if previous_end < t["date"] <= end]
                counted = [t for t in month if not t.get("transfer") and not t["isInterest"]]
                row["moneyIn"] = sum((t["amount"] for t in counted if t["amount"] > 0), Decimal(0))
                row["moneyOut"] = -sum((t["amount"] for t in counted if t["amount"] < 0), Decimal(0))
                row["interest"] = sum((t["amount"] for t in month if t["isInterest"]), Decimal(0))
            rows.append(row)
            previous_end = end
        if len(members) > 1:
            report.add("Merged accounts", f"{account}: {', '.join(sorted(members))}")
    return rows


def holding_key(item: dict) -> str:
    return item["isin"] or item["instrument"].upper()


def assemble_brokers(statements: list[Statement], config: Config, report: Report) -> list[dict]:
    sources = by_source([s for s in statements if s.kind == "broker" and not s.failed])
    trades: list[tuple[Statement, dict]] = []
    for source, group in sources.items():
        held: dict[str, Decimal] = defaultdict(Decimal)
        for statement in group:
            lines = sorted((t for p in statement.data["pages"] for t in p["transactions"]), key=lambda t: t["date"])
            for line in lines:
                trades.append((statement, line))
                key = holding_key(line) if (line["isin"] or line["instrument"]) else None
                if key is None or line["quantity"] is None:
                    continue
                if line["type"] in ("buy", "transferIn"):
                    held[key] += line["quantity"]
                elif line["type"] in ("sell", "transferOut"):
                    held[key] -= line["quantity"]
                elif line["type"] == "split" and line["ratio"] is not None:
                    held[key] *= line["ratio"]
            listed = {holding_key(h): h["quantity"] for p in statement.data["pages"] for h in p["holdings"]}
            if listed:
                for key in sorted(set(listed) | {k for k, v in held.items() if v != 0}):
                    if listed.get(key, Decimal(0)) != held.get(key, Decimal(0)):
                        report.add("Holdings that differ from the trades",
                                   f"{source}, {statement.last_day}: {key}: the statement lists "
                                   f"{money(listed.get(key, Decimal(0)))}, the trades give "
                                   f"{money(held.get(key, Decimal(0)))}")
    # Depot transfers between two statement accounts merged into one library account cancel.
    outs = [(s, t) for s, t in trades if t["type"] == "transferOut"]
    ins = [(s, t) for s, t in trades if t["type"] == "transferIn"]
    dropped = set()
    for out_statement, out in outs:
        for in_statement, came in ins:
            if (id(came) in dropped or in_statement.source == out_statement.source
                    or in_statement.account != out_statement.account
                    or holding_key(came) != holding_key(out) or came["quantity"] != out["quantity"]
                    or abs((came["date"] - out["date"]).days) > config.depot_transfer_days):
                continue
            dropped.update({id(out), id(came)})
            report.add("Depot transfers merged away", f"{out_statement.account}: {money(out['quantity'])} "
                       f"{holding_key(out)}, {out['date']} → {came['date']}")
            break
    rows = []
    for statement, line in trades:
        if id(line) in dropped:
            continue
        if line["type"] == "transferIn":
            report.add("Transfers in kept (their cost is unknown)", f"{statement.account}: {line['date']} "
                       f"{money(line['quantity'])} {holding_key(line)}")
        if line["type"] == "other":
            report.add("Trade types to map (retire import --type \"word=type\")",
                       f"{statement.account}: \"{line['typeText']}\" on {line['date']}")
        rows.append({
            "date": line["date"], "account": statement.account,
            "type": line["typeText"] if line["type"] == "other" else line["type"],
            "isin": line["isin"] or "", "instrument": line["instrument"],
            "quantity": line["quantity"], "price": line["price"], "currency": line["priceCurrency"] or "",
            "amount": line["amount"], "fees": line["fees"], "tax": line["tax"], "ratio": line["ratio"],
            "note": line["description"],
        })
    return sorted(rows, key=lambda r: (r["account"], r["date"]))


def assemble_debts(statements: list[Statement], report: Report) -> list[dict]:
    """One row per statement date of each library account: the sum of what each of its cards or
    loans owed on that date, by its latest statement, while it has statements."""
    owed: dict[str, list[tuple[date, Decimal]]] = {}
    accounts: dict[str, list[str]] = defaultdict(list)
    for source, group in by_source([s for s in statements if s.kind in ("card", "loan") and not s.failed]).items():
        previous = None
        series = []
        for statement in sorted(group, key=lambda s: s.data["statementDate"]):
            data = statement.data
            if previous and data["previousBalance"] is not None and data["previousBalance"] != previous["balanceOwed"]:
                report.add("Balances that don't carry over", f"{source}: {money(previous['balanceOwed'])} owed on "
                           f"{previous['statementDate']}, but the next statement starts from "
                           f"{money(data['previousBalance'])}")
            series.append((data["statementDate"], data["balanceOwed"]))
            previous = data
        owed[source] = series
        accounts[group[0].account].append(source)
    rows = []
    for account, members in sorted(accounts.items()):
        for on in sorted({d for m in members for d, _ in owed[m]}):
            total = Decimal(0)
            for m in members:
                if owed[m][0][0] <= on <= owed[m][-1][0]:
                    total += [v for d, v in owed[m] if d <= on][-1]
            # Written the way the library stores debts: negative, positive when in credit.
            rows.append({"date": on, "account": account, "balance": -total})
    return rows


def movements(statements: list[Statement]) -> list[Movement]:
    result = []
    for statement in statements:
        if statement.failed:
            continue
        if statement.kind == "bank":
            for line in bank_lines(statement):
                if not line["isInterest"]:
                    result.append(Movement(statement.account, statement.source, line["date"], line["amount"], line))
        elif statement.kind == "broker":
            for page in statement.data["pages"]:
                for line in page["transactions"]:
                    if line["type"] in ("deposit", "withdrawal") and line["amount"] is not None:
                        # A deposit into the broker is money out of the bank.
                        result.append(Movement(statement.account, statement.source, line["date"], line["amount"], line))
    return result


def write_csv(path: Path, columns: list[str], rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(columns)
        for row in rows:
            writer.writerow([money(v) if isinstance(v, Decimal) else (v.isoformat() if isinstance(v, date) else
                             ("" if v is None else v)) for v in (row[c] for c in columns)])


CASH_COLUMNS = ["date", "account", "balance", "moneyIn", "moneyOut", "interest"]
DEBT_COLUMNS = ["date", "account", "balance"]
TRADE_COLUMNS = ["date", "account", "type", "isin", "instrument", "quantity", "price", "currency",
                 "amount", "fees", "tax", "ratio", "note"]

PLAIN_FORMAT = {"date": {"pattern": "yyyy-MM-dd"}, "empty": "skip", "number": {"decimal": ".", "thousands": ""}}
PLAIN_FILE = {"delimiter": ",", "encoding": "utf-8", "excludeRows": [], "headerRow": 1}


def profiles() -> dict[str, dict]:
    """Import profiles for the CSVs, to copy into the library's imports/ folder."""
    balances = {
        "columns": [
            {"field": "date", "header": "date"},
            {"field": "account", "header": "account"},
            {"field": "value", "header": "balance", "target": "balance"},
            # The importer has no moneyIn, moneyOut or interest target yet.
            {"field": "ignore", "header": "moneyIn"},
            {"field": "ignore", "header": "moneyOut"},
            {"field": "ignore", "header": "interest"},
        ],
        "defaults": PLAIN_FORMAT, "file": PLAIN_FILE, "id": "backfill-cash", "layout": "long",
        "name": "Backfill: cash and savings", "onConflict": "keep", "target": "balance",
    }
    debts = {
        "columns": [
            {"field": "date", "header": "date"},
            {"field": "account", "header": "account"},
            {"field": "value", "header": "balance", "target": "balance"},
        ],
        "defaults": {**PLAIN_FORMAT, "liabilitySign": "asWritten"}, "file": PLAIN_FILE, "id": "backfill-debts",
        "layout": "long",
        "name": "Backfill: cards and loans", "onConflict": "keep", "target": "balance",
    }
    trades = {
        "columns": [
            {"field": "date", "header": "date"},
            {"field": "account", "header": "account"},
            {"field": "type", "header": "type"},
            {"field": "instrument", "header": "isin"},
            {"field": "instrument", "header": "instrument"},
            {"field": "quantity", "header": "quantity"},
            {"field": "price", "header": "price"},
            {"field": "currency", "header": "currency"},
            {"field": "amount", "header": "amount"},
            {"field": "fees", "header": "fees"},
            {"field": "tax", "header": "tax"},
            {"field": "ratio", "header": "ratio"},
            {"field": "note", "header": "note"},
        ],
        "defaults": {**PLAIN_FORMAT, "amountSign": "asWritten"}, "file": PLAIN_FILE, "id": "backfill-trades",
        "layout": "trades", "name": "Backfill: broker trades", "onConflict": "keep",
        "tradeTypes": {t: t for t in sorted(TRADE_TYPES - {"other"})},
    }
    return {"backfill-cash": balances, "backfill-debts": debts, "backfill-trades": trades}


def assemble(config: Config, files: list[Path]) -> None:
    report = Report()
    statements = map_accounts(load_statements(config, files, report), config, report)
    pairs = match_transfers(movements(statements), config.transfer_days)
    cash = assemble_banks(statements, report)
    trades = assemble_brokers(statements, config, report)
    debts = assemble_debts(statements, report)
    output = config.output
    write_csv(output / "cash.csv", CASH_COLUMNS, cash)
    write_csv(output / "debts.csv", DEBT_COLUMNS, debts)
    write_csv(output / "trades.csv", TRADE_COLUMNS, trades)
    for name, profile in profiles().items():
        path = output / "profiles" / f"{name}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(profile, indent=2, sort_keys=True) + "\n")
    summary = [
        f"{len(files)} PDFs, {sum(not s.failed for s in statements)} statements used",
        f"{len(cash)} month ends for cash and savings ({output / 'cash.csv'})",
        f"{len(debts)} card and loan balances ({output / 'debts.csv'})",
        f"{len(trades)} broker trades ({output / 'trades.csv'})",
        f"transfers between your accounts, left out of money in and out: {pairs}",
    ]
    lines = ["# Backfill report", ""] + [f"- {line}" for line in summary]
    for section, items in report.sections.items():
        lines += ["", f"## {section} ({len(items)})", ""] + [f"- {item}" for item in items]
    (output / "report.md").write_text("\n".join(lines) + "\n")
    log("\n".join(summary))
    for section, items in report.sections.items():
        log(f"  {section}: {len(items)}")
    log(f"Report: {output / 'report.md'}")

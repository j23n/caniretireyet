# /// script
# requires-python = ">=3.11"
# dependencies = ["mlx-lm"]
# ///
"""Backfill the library from PDF statements with a local model.

    uv run backfill.py                            # every account folder
    uv run backfill.py --account current-account  # one account folder

Set the paths below, then run. Every model reply is cached in WORK, so you can stop and
start again, change a prompt and rerun, or raise LIMIT after a pilot. README.md explains
the stages and what to do with the CSVs.
"""

import argparse
from pathlib import Path

import pipeline

# Where the PDFs are: one folder per library account, named by its ID, such as
# Statements/current-account/. Folders inside an account's folder hold statement accounts
# merged into it, such as an old current account.
STATEMENTS = Path("~/Documents/Statements").expanduser()
# The cache: extracted text and every model reply, one folder per PDF.
WORK = Path("~/statement-backfill/work").expanduser()
# Where the CSVs, import profiles and report.md go.
OUTPUT = Path("~/statement-backfill/output").expanduser()

# The model that reads every statement, and the one that tries again on those whose numbers
# don't add up (None to skip). Each is loaded only when it's needed.
MODEL = "mlx-community/Qwen3-30B-A3B-Instruct-2507-4bit"
RETRY_MODEL = "mlx-community/Qwen2.5-32B-Instruct-4bit"

# Only the first LIMIT PDFs of this run, for a pilot (None for all), or only these file names.
LIMIT = 20
ONLY: list[str] = []

# Print every model reply.
SHOW_REPLIES = False

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Backfill the library from PDF statements.")
    parser.add_argument("--account", metavar="ID",
                        help="read only this account's folder; the CSVs still cover every folder read so far")
    arguments = parser.parse_args()
    pipeline.run(pipeline.Config(
        statements=STATEMENTS, work=WORK, output=OUTPUT, account=arguments.account,
        model=MODEL, retry_model=RETRY_MODEL, limit=LIMIT, only=ONLY, show_replies=SHOW_REPLIES,
    ))

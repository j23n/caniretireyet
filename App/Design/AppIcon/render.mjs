// Renders the icon SVGs to 1024 px PNGs in ./build with Playwright's Chromium.
// Usage: node render.mjs   (needs `npm i -g playwright`; then python3 build.py)
import { chromium } from 'playwright';
import { readFileSync, mkdirSync } from 'node:fs';

const names = ['AppIcon', 'AppIcon-Dark', 'AppIcon-Tinted', 'AppIcon-Mac'];
mkdirSync('build', { recursive: true });
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1024, height: 1024 } });
for (const name of names) {
  await page.setContent(`<body style="margin:0;background:transparent">${readFileSync(`${name}.svg`, 'utf8')}</body>`);
  await page.screenshot({ path: `build/${name}.png`, clip: { x: 0, y: 0, width: 1024, height: 1024 }, omitBackground: true });
}
await browser.close();

import puppeteer from 'puppeteer';
import { spawn } from 'node:child_process';
import ffmpeg from 'ffmpeg-static';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import fs from 'node:fs';

const FPS = 30;
const dir = path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const browser = await puppeteer.launch({ args: ['--no-sandbox', '--font-render-hinting=none'] });
const page = await browser.newPage();
await page.setViewport({ width: 1920, height: 1080, deviceScaleFactor: 1 });
await page.goto(pathToFileURL(path.join(dir, 'index.html')).href);
await page.evaluate(() => document.fonts.ready);

const arg = process.argv[2];
if (arg === 'stills') {
  fs.mkdirSync(path.join(dir, 'stills'), { recursive: true });
  for (const t of process.argv[3].split(',').map(Number)) {
    await page.evaluate((t) => window.render(t), t);
    await page.screenshot({ path: path.join(dir, 'stills', `t${t}.png`) });
  }
  await browser.close();
  process.exit(0);
}

const out = process.argv[3] || path.join(dir, 'feather-promo.mp4');
const total = await page.evaluate(() => window.TOTAL);
const ff = spawn(ffmpeg, [
  '-y', '-f', 'image2pipe', '-framerate', String(FPS), '-i', '-',
  '-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-pix_fmt', 'yuv420p',
  '-movflags', '+faststart', out,
], { stdio: ['pipe', 'inherit', 'inherit'] });

const n = total * FPS;
for (let i = 0; i < n; i++) {
  await page.evaluate((t) => window.render(t), i / FPS);
  const buf = await page.screenshot({ type: 'jpeg', quality: 95 });
  if (!ff.stdin.write(buf)) await new Promise((r) => ff.stdin.once('drain', r));
  if (i % 60 === 0) console.log(`frame ${i}/${n}`);
}
ff.stdin.end();
await new Promise((r) => ff.on('close', r));
await browser.close();
console.log('done', out);

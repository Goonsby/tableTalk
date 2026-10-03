/*
 * Browser smoke/regression checks for the standalone demo.
 * Install Playwright outside this repository if desired, then run:
 *   node --test tests/browser-demo.spec.cjs
 * Optional: PLAYWRIGHT_MODULE (module path), BROWSER_EXECUTABLE_PATH,
 * DEMO_SCREENSHOT_DIR (directory for desktop/phone/narrow PNG evidence).
 */
'use strict';

const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

const demoPath = path.resolve(__dirname, '../demo/index.html');
const demoURL = pathToFileURL(demoPath).href;
const sizes = [
  { name: 'desktop', width: 1440, height: 1000 },
  { name: 'phone', width: 390, height: 844 },
  { name: 'narrow', width: 320, height: 740 },
];

async function turnCount(page) {
  return page.locator('#english-captions .turn').count();
}

async function assertEmpty(page) {
  assert.equal(await turnCount(page), 0);
  assert.equal(await page.locator('#spanish-captions .turn').count(), 0);
  assert.equal(await page.locator('#turn-count').innerText(), '0 / 12');
}

async function assertNoOverflow(page) {
  const dimensions = await page.evaluate(() => ({
    viewport: document.documentElement.clientWidth,
    document: document.documentElement.scrollWidth,
    body: document.body.scrollWidth,
  }));
  assert.ok(dimensions.document <= dimensions.viewport + 1, JSON.stringify(dimensions));
  assert.ok(dimensions.body <= dimensions.viewport + 1, JSON.stringify(dimensions));
}

test('demo has no active networking, persistence, or audio integrations', () => {
  const html = fs.readFileSync(demoPath, 'utf8');
  const scripts = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi)]
    .map(match => match[1]).join('\n');
  assert.ok(scripts.trim(), 'The standalone page includes its behavior inline');
  assert.doesNotMatch(html, /<(?:script|iframe)\b[^>]*\bsrc\s*=/i);
  assert.doesNotMatch(html, /<link\b[^>]*\brel\s*=\s*["']?(?:stylesheet|preconnect|dns-prefetch)/i);
  assert.doesNotMatch(html, /<(?:audio|video)\b/i);
  assert.doesNotMatch(scripts, /\b(?:fetch|XMLHttpRequest|WebSocket|EventSource|Worker|SharedWorker|localStorage|sessionStorage|indexedDB|caches|SpeechRecognition|webkitSpeechRecognition|AudioContext|webkitAudioContext)\b/);
  assert.doesNotMatch(scripts, /\b(?:getUserMedia|sendBeacon|serviceWorker)\b|document\s*\.\s*cookie/);
});

test('standalone demo works at desktop and mobile widths', { timeout: 120000 }, async t => {
  const browser = await chromium.launch({
    headless: true,
    ...(process.env.BROWSER_EXECUTABLE_PATH ? { executablePath: process.env.BROWSER_EXECUTABLE_PATH } : {}),
  });
  try {
    for (const size of sizes) {
      await t.test(`${size.name}: ${size.width} x ${size.height}`, async () => {
        const context = await browser.newContext({ viewport: { width: size.width, height: size.height } });
        const page = await context.newPage();
        const requests = [];
        const errors = [];
        page.on('request', request => requests.push(request.url()));
        page.on('pageerror', error => errors.push(error.message));
        await context.route('**/*', route => route.request().url().startsWith('file:')
          ? route.continue() : route.abort());
        await page.addInitScript(() => {
          window.__forbiddenCalls = [];
          const block = name => function () {
            window.__forbiddenCalls.push(name);
            throw new Error(`Unexpected browser API: ${name}`);
          };
          for (const name of ['fetch', 'XMLHttpRequest', 'WebSocket', 'EventSource', 'Audio', 'AudioContext', 'webkitAudioContext', 'SpeechRecognition', 'webkitSpeechRecognition']) {
            if (name in window) window[name] = block(name);
          }
          for (const name of ['getItem', 'setItem', 'removeItem', 'clear']) {
            Storage.prototype[name] = block(`storage.${name}`);
          }
          if (navigator.mediaDevices) navigator.mediaDevices.getUserMedia = block('getUserMedia');
          navigator.sendBeacon = block('sendBeacon');
          if (window.speechSynthesis) window.speechSynthesis.speak = block('speechSynthesis.speak');
          if (window.indexedDB) window.indexedDB.open = block('indexedDB.open');
        });
        try {
          await page.clock.install();
          await page.goto(demoURL);
          assert.equal(await turnCount(page), 1, 'Initial example visible');
          await assertNoOverflow(page);
          if (process.env.DEMO_SCREENSHOT_DIR) {
            fs.mkdirSync(process.env.DEMO_SCREENSHOT_DIR, { recursive: true });
            await page.screenshot({ path: path.join(process.env.DEMO_SCREENSHOT_DIR, `${size.name}.png`), fullPage: true });
          }

          // Both source languages render a turn to both listeners.
          await page.locator('#clear').click();
          await assertEmpty(page);
          for (const [selector, language] of [['#english-talk', 'en'], ['#spanish-talk', 'es']]) {
            await page.locator(selector).click();
            assert.equal(await page.locator(`#english-captions .turn[data-source="${language}"]`).count(), 1);
            assert.equal(await page.locator(`#spanish-captions .turn[data-source="${language}"]`).count(), 1);
            const sourcePanel = language === 'en' ? '#english-captions' : '#spanish-captions';
            const listenerPanel = language === 'en' ? '#spanish-captions' : '#english-captions';
            assert.equal(await page.locator(`${sourcePanel} .turn:last-child .pending`).count(), 0);
            assert.equal(await page.locator(`${listenerPanel} .turn:last-child .pending`).count(), 1,
              'The listener sees a pending translation before the sample delay');
            await page.clock.runFor(650);
            assert.equal(await page.locator('.caption-primary.pending').count(), 0);
            const english = page.locator('#english-captions .turn').last();
            const spanish = page.locator('#spanish-captions .turn').last();
            assert.equal(await english.locator('.caption-primary').innerText(), await spanish.locator('.caption-secondary').innerText());
            assert.equal(await spanish.locator('.caption-primary').innerText(), await english.locator('.caption-secondary').innerText());
          }
          assert.equal(await turnCount(page), 2);
          await assertNoOverflow(page);

          // Clearing while translation is pending cannot restore a removed turn.
          await page.locator('#english-talk').click();
          await page.locator('#clear').click();
          await page.clock.runFor(1000);
          await assertEmpty(page);

          // Every scenario plays alternating English and Spanish samples.
          const scenarios = await page.locator('#scenario option').evaluateAll(options => options.map(option => option.value));
          assert.deepEqual(scenarios, ['welcome', 'plans', 'clarity']);
          const scenarioTexts = [];
          for (const scenario of scenarios) {
            await page.locator('#scenario').selectOption(scenario);
            await page.locator('#clear').click();
            await page.locator('#play').click();
            await page.clock.runFor(8000);
            assert.equal(await turnCount(page), 4, `Four ${scenario} turns`);
            for (const language of ['en', 'es']) {
              assert.equal(await page.locator(`#english-captions .turn[data-source="${language}"]`).count(), 2);
            }
            scenarioTexts.push(await page.locator('#english-captions').innerText());
          }
          assert.equal(new Set(scenarioTexts).size, 3, 'Scenario content changes');

          // Clearing a running sample cancels both its playback and translation timers.
          await page.locator('#clear').click();
          await page.locator('#play').click();
          await page.locator('#clear').click();
          await page.clock.runFor(10000);
          await assertEmpty(page);

          for (let index = 0; index < 15; index++) {
            await page.locator(index % 2 ? '#spanish-talk' : '#english-talk').click();
            await page.clock.runFor(650);
          }
          assert.equal(await turnCount(page), 12, 'History is bounded');
          assert.equal(await page.locator('#spanish-captions .turn').count(), 12);
          const ids = await page.locator('#english-captions .turn').evaluateAll(turns => turns.map(turn => Number(turn.dataset.turnId)));
          assert.equal(ids.at(-1) - ids[0], 11, 'The oldest turns are removed first');
          assert.equal(await page.locator('#turn-count').innerText(), '12 / 12');
          await assertNoOverflow(page);

          await page.locator('#text-size').click();
          await assertNoOverflow(page);
          await page.locator('#layout-toggle').click();
          assert.equal(await page.locator('#rotate').isDisabled(), true);
          await assertNoOverflow(page);
          await page.locator('#layout-toggle').click();
          await page.locator('#rotate').click();
          await assertNoOverflow(page);

          // Opening setup clears the temporary conversation.
          await page.locator('#setup').click();
          assert.equal(await page.locator('#setup-dialog').isVisible(), true);
          await assertEmpty(page);
          await assertNoOverflow(page);
          await page.locator('#close-setup').click();
          assert.equal(await page.locator('#setup-dialog').isVisible(), false);

          // Simulate the browser's visibility event deterministically in headless mode.
          await page.locator('#play').click();
          await page.evaluate(() => {
            Object.defineProperty(document, 'hidden', { configurable: true, get: () => true });
            Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'hidden' });
            document.dispatchEvent(new Event('visibilitychange'));
          });
          await page.clock.runFor(10000);
          await assertEmpty(page);
          assert.deepEqual(await page.evaluate(() => window.__forbiddenCalls), []);
          assert.deepEqual(errors, []);
          assert.deepEqual(requests.filter(url => url !== demoURL), [], 'No resource or network requests');
        } finally {
          await context.close();
        }
      });
    }
  } finally {
    await browser.close();
  }
});

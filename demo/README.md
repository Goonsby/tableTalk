# TableTalk browser demo

`index.html` is the complete static public preview. Copy that file into any static web root; it has no build step, package dependency, backend, external font, image, or script. It also works when opened directly from disk. The native Android and iPhone implementations are separate and unchanged.

To preview locally from the repository root:

```sh
python -m http.server 8080 --directory demo
```

Open `http://localhost:8080`. Deploy only `index.html`; this README and the test tooling are not runtime dependencies.

## What it demonstrates

- Two opposing English/Spanish caption panels; swap seats or read both upright.
- Three prewritten conversations, automatic sample playback, and manual turns in either language.
- An explicitly simulated caption delay, larger text, and a twelve-turn history limit.
- Clear/reset, scenario changes, opening the app guide, leaving the tab, and navigating away cancel pending sample work and clear history.
- Native app setup links and the distinction between browser samples and native on-device processing.

## Privacy and limitations

The page has no microphone or speech permission request, text-entry form, real recognition/translation engine, or language model. All captions are fixed samples. It does not use browser storage, cookies, analytics, or background requests. The inline Content Security Policy forbids connections and media loads. External GitHub links are followed only when the visitor chooses them.

The web host can still log ordinary page requests (for example IP address and user agent); those server logs are outside this static page. Browser screenshots remain possible. This demo does not prove native phone readiness, translation accuracy, or offline operation.

The hosting owner can additionally send `Permissions-Policy: microphone=(), camera=(), geolocation=()` and standard HTTPS/security headers. This artifact makes no server, DNS, certificate, or reverse-proxy changes.

## Verification

Browser tests use Playwright with Node's built-in test runner:

```sh
node --test tests/browser-demo.spec.cjs
```

Install Playwright as development tooling or set `PLAYWRIGHT_MODULE` to an existing installation. Optional `BROWSER_EXECUTABLE_PATH` selects a local Chrome/Chromium binary. Optional `DEMO_SCREENSHOT_DIR` records screenshots. Tests exercise desktop (1440×1000), phone (390×844), narrow phone (320×740), caption/history controls, cancellation and clearing, layout overflow, and absence of networking/persistence/audio integration. They run in an isolated browser context, not a personal browser profile.

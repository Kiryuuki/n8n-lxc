# Browserless Custom Script

Use this when the `n8n-nodes-playwright` community node fails before your script runs.

Root cause: the Playwright node validates a local browser binary first. Browserless does not need local Chromium, but the community node still checks paths like:

```text
/opt/n8n/custom/node_modules/n8n-nodes-playwright/dist/nodes/browsers/chromium-1223/chrome-linux/chrome
```

## Option A: n8n Code Node

Prereqs in `/etc/n8n/n8n.env`:

```env
NODE_FUNCTION_ALLOW_EXTERNAL=playwright,playwright-core
NODE_FUNCTION_ALLOW_BUILTIN=*
NODE_PATH=/opt/n8n/custom/node_modules
BROWSERLESS_WS_URL=ws://browserless.example.internal:3000?token=replace_with_token&timeout=55000
```

Current local Browserless instance: `ws://192.168.100.60:3111`. Keep the token only in `/etc/n8n/n8n.env`, not in tracked docs.

Code node mode: `Run Once for All Items`

```javascript
const { chromium } = require("playwright-core");

async function scrape(url) {
  const browserlessUrl = $env.BROWSERLESS_WS_URL || process.env.BROWSERLESS_WS_URL;
  if (!browserlessUrl) throw new Error("BROWSERLESS_WS_URL is missing");

  const browser = await chromium.connectOverCDP(browserlessUrl, { timeout: 30000 });

  try {
    const context = browser.contexts()[0] || await browser.newContext({
      locale: "en-PH",
      viewport: { width: 1365, height: 900 },
      userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
    });

    const page = await context.newPage();
    await page.goto(url, { waitUntil: "domcontentloaded", timeout: 45000 });
    await page.waitForLoadState("networkidle", { timeout: 15000 }).catch(() => {});

    return await page.evaluate(() => ({
      url: location.href,
      title: document.title,
      h1: document.querySelector("h1")?.innerText?.trim() || null,
      textSample: document.body?.innerText?.replace(/\s+/g, " ").trim().slice(0, 500) || "",
    }));
  } finally {
    await browser.close();
  }
}

const input = $input.all();
const targets = input.length
  ? input.map((item) => item.json.url || "https://example.com")
  : ["https://example.com"];

const results = [];
for (const url of targets) {
  results.push({ json: { ok: true, scrapedAt: new Date().toISOString(), ...(await scrape(url)) } });
}

return results;
```

## Option B: Execute Command Node

Run from the LXC:

```bash
node /path/to/n8n-lxc/scripts/browserless-smoke.js https://example.com
```

If the repo is deployed under `/opt/n8n/n8n-lxc`:

```bash
node /opt/n8n/n8n-lxc/scripts/browserless-smoke.js https://example.com
```

Expected output:

```json
{
  "ok": true,
  "scrapedAt": "2026-05-15T00:00:00.000Z",
  "result": {
    "url": "https://example.com/",
    "title": "Example Domain",
    "h1": "Example Domain",
    "textSample": "Example Domain This domain is for use in illustrative examples..."
  }
}
```

Dash

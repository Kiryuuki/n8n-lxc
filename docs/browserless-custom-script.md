# Browserless Custom Script

Use this when the `n8n-nodes-playwright` community node fails before your script runs.

Root cause: the Playwright node validates a local browser binary first. Browserless does not need local Chromium, but the community node still checks paths like:

```text
/opt/n8n/custom/node_modules/n8n-nodes-playwright/dist/nodes/browsers/chromium-1223/chrome-linux/chrome
```

## Recommended: Execute Command Node

Use this path for n8n `2.x`. Playwright can fail inside the Code node sandbox with:

```text
Cannot assign to read only property 'stackTraceLimit'
```

Deploy the script somewhere the `n8n` service user can read:

```bash
cd ~/n8n-lxc
git pull
mkdir -p /opt/n8n/scripts
cp scripts/browserless-smoke.js /opt/n8n/scripts/browserless-scrape.js
chown -R n8n:n8n /opt/n8n/scripts
chmod 755 /opt/n8n/scripts/browserless-scrape.js
```

Execute Command node:

```bash
node /opt/n8n/scripts/browserless-scrape.js "{{$json.url || 'https://example.com'}}"
```

Then parse stdout JSON in the next node.

## Alternative: n8n Code Node

Prereqs in `/etc/n8n/n8n.env`:

```env
NODE_FUNCTION_ALLOW_EXTERNAL=playwright,playwright-core
NODE_FUNCTION_ALLOW_BUILTIN=*
N8N_BLOCK_ENV_ACCESS_IN_NODE=false
NODE_PATH=/opt/n8n/custom/node_modules
BROWSERLESS_WS_URL=ws://browserless.example.internal:3000?token=replace_with_token&timeout=55000
N8N_CORS_ALLOWED_ORIGINS=https://n8n.example.com,https://claude.ai,https://claude.com
N8N_CORS_ALLOW_CREDENTIALS=true
N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true
```

Restart n8n after adding `N8N_BLOCK_ENV_ACCESS_IN_NODE=false`.

Keep the live Browserless host and token only in `/etc/n8n/n8n.env`, not in tracked docs.

Warning: this can still fail in n8n `2.x` because the Code node VM freezes native globals that Playwright expects to patch.

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

## Standalone Smoke Test

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

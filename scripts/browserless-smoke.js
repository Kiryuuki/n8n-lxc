#!/usr/bin/env node

const fs = require("fs");

function loadEnvFile(path) {
  if (!fs.existsSync(path)) return;

  for (const line of fs.readFileSync(path, "utf8").split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#") || !trimmed.includes("=")) continue;

    const index = trimmed.indexOf("=");
    const key = trimmed.slice(0, index).trim();
    let value = trimmed.slice(index + 1).trim();
    value = value.replace(/^['"]|['"]$/g, "");

    if (key && process.env[key] === undefined) {
      process.env[key] = value;
    }
  }
}

function loadPlaywrightCore() {
  try {
    return require("playwright-core");
  } catch (error) {
    return require("/opt/n8n/custom/node_modules/playwright-core");
  }
}

async function scrape(url) {
  loadEnvFile("/etc/n8n/n8n.env");

  const browserlessUrl = process.env.BROWSERLESS_WS_URL;
  if (!browserlessUrl) {
    throw new Error("BROWSERLESS_WS_URL is missing. Set it in /etc/n8n/n8n.env.");
  }

  const { chromium } = loadPlaywrightCore();
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

async function main() {
  const url = process.argv[2] || "https://example.com";
  const result = await scrape(url);
  console.log(JSON.stringify({ ok: true, scrapedAt: new Date().toISOString(), result }, null, 2));
}

main().catch((error) => {
  console.error(JSON.stringify({ ok: false, error: error.message }, null, 2));
  process.exit(1);
});

#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/n8n"
BROWSERS_DIR="/home/n8n/.cache/ms-playwright"
ENV_FILE="/etc/n8n/n8n.env"

check_command() {
  local name="$1"
  local command="$2"

  if bash -lc "${command}" >/dev/null 2>&1; then
    echo "[OK] ${name}"
  else
    echo "[FAIL] ${name}"
    return 1
  fi
}

check_file() {
  local path="$1"

  if [[ -f "${path}" ]]; then
    echo "[OK] ${path}"
  else
    echo "[FAIL] ${path} missing"
    return 1
  fi
}

load_env() {
  if [[ -f "${ENV_FILE}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
  fi
}

check_http() {
  if curl -fsS http://127.0.0.1:5678/healthz >/dev/null 2>&1; then
    echo "[OK] n8n healthz"
    return
  fi

  if curl -fsS http://127.0.0.1:5678 >/dev/null 2>&1; then
    echo "[OK] n8n port 5678"
    return
  fi

  echo "[FAIL] n8n HTTP check"
  return 1
}

check_playwright() {
  sudo -H -u n8n env PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-${BROWSERS_DIR}}" \
    bash -lc "cd '${APP_DIR}/custom' && node -" <<'NODE'
const { chromium } = require('/opt/n8n/custom/node_modules/playwright');

(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();
  await page.setContent('<h1>ok</h1>');
  const text = await page.textContent('h1');
  await browser.close();
  if (text !== 'ok') throw new Error('Unexpected page text');
})();
NODE
  echo "[OK] local Playwright Chromium"
}

check_browserless() {
  if [[ -z "${BROWSERLESS_WS_URL:-}" || "${BROWSERLESS_WS_URL}" == *replace_with* ]]; then
    echo "[SKIP] Browserless URL not configured"
    return
  fi

  sudo -H -u n8n env BROWSERLESS_WS_URL="${BROWSERLESS_WS_URL}" bash -lc "cd '${APP_DIR}/custom' && node -" <<'NODE'
const { chromium } = require('/opt/n8n/custom/node_modules/playwright-core');

(async () => {
  const browser = await chromium.connectOverCDP(process.env.BROWSERLESS_WS_URL);
  await browser.close();
})();
NODE
  echo "[OK] Browserless CDP"
}

main() {
  load_env
  check_command "node" "node --version | grep -Eq '^v22\\.'"
  check_command "npm" "npm --version"
  check_command "n8n binary" "command -v n8n"
  check_command "postgres service" "systemctl is-active --quiet postgresql"
  check_command "n8n service" "systemctl is-active --quiet n8n"
  check_file "${ENV_FILE}"
  check_file "${APP_DIR}/execution-hooks.js"
  check_http
  check_playwright
  check_browserless
  journalctl -u n8n -n 100 --no-pager | grep -q "n8n IS READY AND HOOKS ARE ACTIVE" && echo "[OK] hook loaded"
}

main "$@"

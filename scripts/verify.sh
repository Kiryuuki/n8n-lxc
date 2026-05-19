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
  [[ -f "${ENV_FILE}" ]] || return

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    [[ -z "${line}" || "${line}" == \#* || "${line}" != *=* ]] && continue

    local key="${line%%=*}"
    local value="${line#*=}"
    [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue

    value="${value#\'}"
    value="${value%\'}"
    value="${value#\"}"
    value="${value%\"}"
    printf -v "${key}" '%s' "${value}"
    export "${key}"
  done < "${ENV_FILE}"
}

load_env_value() {
  local key="$1"
  local value=""

  value="$(grep -E "^${key}=" "${ENV_FILE}" | tail -n 1 | cut -d= -f2- || true)"
  value="${value#\'}"
  value="${value%\'}"
  value="${value#\"}"
  value="${value%\"}"
  printf '%s' "${value}"
}

run_as_n8n() {
  if command -v runuser >/dev/null 2>&1; then
    runuser -u n8n -- "$@"
  else
    sudo -n -u n8n "$@"
  fi
}

browserless_timeout_ms() {
  local url="$1"
  local timeout="55000"

  if [[ "${url}" =~ (^|[?&])timeout=([0-9]+) ]]; then
    timeout="${BASH_REMATCH[2]}"
  fi

  printf '%s' "${timeout}"
}

sanitize_browserless_url() {
  local url="$1"
  printf '%s' "${url}" | sed -E 's#token=[^&]+#token=***#'
}

check_http() {
  local attempt

  for attempt in {1..30}; do
    if curl -fsS http://127.0.0.1:5678/healthz >/dev/null 2>&1; then
      echo "[OK] n8n healthz"
      return
    fi

    if curl -fsS http://127.0.0.1:5678 >/dev/null 2>&1; then
      echo "[OK] n8n port 5678"
      return
    fi

    sleep 2
  done

  echo "[FAIL] n8n HTTP check"
  return 1
}

find_package_local_chromium() {
  local base="/opt/n8n/custom/node_modules/n8n-nodes-playwright/dist/nodes/browsers"
  local chromium_dir
  for chromium_dir in "${base}"/chromium-*; do
    [[ -d "${chromium_dir}" ]] || continue
    if [[ -f "${chromium_dir}/chrome-linux/chrome" ]]; then
      printf '%s\n' "${chromium_dir}/chrome-linux/chrome"
      return 0
    fi
    if [[ -f "${chromium_dir}/chrome-linux64/chrome" ]]; then
      printf '%s\n' "${chromium_dir}/chrome-linux64/chrome"
      return 0
    fi
  done
  return 1
}

check_package_local_chromium_binary() {
  local chromium_bin=""
  local chromium_real_bin=""
  chromium_bin="$(find_package_local_chromium || true)"

  if [[ -z "${chromium_bin}" ]]; then
    echo "[FAIL] package-local Chromium binary missing under n8n-nodes-playwright browsers/"
    return 1
  fi

  if ! [[ -x "${chromium_bin}" ]]; then
    echo "[FAIL] Chromium exists but is not executable: ${chromium_bin}"
    return 1
  fi

  chromium_real_bin="$(readlink -f "${chromium_bin}" 2>/dev/null || true)"
  if [[ -z "${chromium_real_bin}" || ! -f "${chromium_real_bin}" ]]; then
    echo "[FAIL] Chromium symlink target is missing or unreadable: ${chromium_bin}"
    return 1
  fi

  if ! [[ -x "${chromium_real_bin}" ]]; then
    echo "[FAIL] Chromium target exists but is not executable: ${chromium_real_bin}"
    return 1
  fi

  if command -v file >/dev/null 2>&1; then
    if ! file -Lb "${chromium_real_bin}" | grep -qi 'ELF'; then
      echo "[FAIL] Chromium binary is not ELF (likely corrupted): ${chromium_real_bin}"
      return 1
    fi
  else
    if ! head -c 4 "${chromium_real_bin}" 2>/dev/null | grep -q $'^\x7fELF$'; then
      echo "[FAIL] Chromium binary header is invalid (likely corrupted): ${chromium_real_bin}"
      return 1
    fi
  fi

  echo "[OK] package-local Chromium binary: ${chromium_bin} -> ${chromium_real_bin}"
}

check_playwright() {
  run_as_n8n env PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-${BROWSERS_DIR}}" \
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
  local browserless_url="${BROWSERLESS_WS_URL:-}"
  local timeout_ms

  if [[ -z "${browserless_url}" ]]; then
    browserless_url="$(load_env_value "BROWSERLESS_WS_URL")"
  fi

  if [[ -z "${browserless_url}" || "${browserless_url}" == *replace_with* ]]; then
    echo "[SKIP] Browserless URL not configured"
    return
  fi

  if [[ "${browserless_url}" != *"?token="* || "${browserless_url}" != *"&timeout="* ]]; then
    echo "[FAIL] Browserless URL is malformed. Expected ?token=...&timeout=..."
    return 1
  fi

  timeout_ms="$(browserless_timeout_ms "${browserless_url}")"
  echo "[INFO] Browserless target: $(sanitize_browserless_url "${browserless_url}")"

  run_as_n8n env BROWSERLESS_WS_URL="${browserless_url}" BROWSERLESS_CONNECT_TIMEOUT="${timeout_ms}" \
    bash -lc "cd '${APP_DIR}/custom' && node -" <<'NODE'
const { chromium } = require('/opt/n8n/custom/node_modules/playwright-core');

(async () => {
  const timeout = Number(process.env.BROWSERLESS_CONNECT_TIMEOUT || 55000);
  const browser = await chromium.connectOverCDP(process.env.BROWSERLESS_WS_URL, { timeout });
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
  check_package_local_chromium_binary
  check_playwright
  check_browserless
  journalctl -u n8n -n 100 --no-pager | grep -q "n8n IS READY AND HOOKS ARE ACTIVE" && echo "[OK] hook loaded"
}

main "$@"

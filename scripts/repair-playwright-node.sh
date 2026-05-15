#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/n8n"
NODE_PACKAGE_DIR="${APP_DIR}/custom/node_modules/n8n-nodes-playwright"
NODE_BROWSERS_DIR="${NODE_PACKAGE_DIR}/dist/nodes/browsers"

log() {
  echo "[repair-playwright-node] $*"
}

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash scripts/repair-playwright-node.sh" >&2
  exit 1
fi

if [[ ! -d "${NODE_PACKAGE_DIR}" ]]; then
  echo "n8n-nodes-playwright not found at ${NODE_PACKAGE_DIR}" >&2
  exit 1
fi

log "Installing Playwright browsers into ${NODE_BROWSERS_DIR}"
mkdir -p "${NODE_BROWSERS_DIR}"
chown -R n8n:n8n "${APP_DIR}/custom"

sudo -H -u n8n env PLAYWRIGHT_BROWSERS_PATH="${NODE_BROWSERS_DIR}" \
  bash -lc "cd '${APP_DIR}/custom' && npx playwright install chromium firefox webkit"

log "Installed browser executables:"
find "${NODE_BROWSERS_DIR}" -type f \( -name chrome -o -name firefox -o -name pw_run.sh \) -print

log "Restarting n8n"
systemctl restart n8n
systemctl status n8n --no-pager

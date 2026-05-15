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

log "Preparing Playwright browsers in ${NODE_BROWSERS_DIR}"
mkdir -p "${NODE_BROWSERS_DIR}"
chown -R n8n:n8n "${APP_DIR}/custom"

if find "${NODE_BROWSERS_DIR}" -maxdepth 3 -type f \( -name chrome -o -name firefox -o -name pw_run.sh \) | grep -q .; then
  log "Existing browser files found; skipping browser download"
else
  sudo -H -u n8n env PLAYWRIGHT_BROWSERS_PATH="${NODE_BROWSERS_DIR}" \
    bash -lc "cd '${APP_DIR}/custom' && npx playwright install chromium firefox webkit"
fi

log "Creating compatibility links for n8n-nodes-playwright"
for chromium_dir in "${NODE_BROWSERS_DIR}"/chromium-*; do
  [[ -d "${chromium_dir}" ]] || continue
  if [[ -x "${chromium_dir}/chrome-linux64/chrome" && ! -e "${chromium_dir}/chrome-linux/chrome" ]]; then
    mkdir -p "${chromium_dir}/chrome-linux"
    ln -s ../chrome-linux64/chrome "${chromium_dir}/chrome-linux/chrome"
  fi
done

for firefox_dir in "${NODE_BROWSERS_DIR}"/firefox-*; do
  [[ -d "${firefox_dir}" ]] || continue
  if [[ -x "${firefox_dir}/firefox/firefox" && ! -e "${firefox_dir}/linux/firefox" ]]; then
    mkdir -p "${firefox_dir}/linux"
    ln -s ../firefox/firefox "${firefox_dir}/linux/firefox"
  fi
done

for webkit_dir in "${NODE_BROWSERS_DIR}"/webkit-*; do
  [[ -d "${webkit_dir}" ]] || continue
  if [[ -x "${webkit_dir}/pw_run.sh" && ! -e "${webkit_dir}/webkit-1/minibrowser-gtk/pw_run.sh" ]]; then
    mkdir -p "${webkit_dir}/webkit-1/minibrowser-gtk"
    ln -s ../../pw_run.sh "${webkit_dir}/webkit-1/minibrowser-gtk/pw_run.sh"
  fi
done

chown -R n8n:n8n "${NODE_BROWSERS_DIR}"

log "Installed browser executables:"
find "${NODE_BROWSERS_DIR}" -type f \( -name chrome -o -name firefox -o -name pw_run.sh \) -print

log "Restarting n8n"
systemctl restart n8n
systemctl status n8n --no-pager

#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/n8n"
NODE_PACKAGE_DIR="${APP_DIR}/custom/node_modules/n8n-nodes-playwright"
NODE_BROWSERS_DIR="${NODE_PACKAGE_DIR}/dist/nodes/browsers"
SETUP_SKIP_CONTENT="console.log('Browser setup skipped: managed by n8n-lxc repair script');"

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

check_writable_dir() {
  local dir="$1"
  local test_file="${dir}/.repair-write-test"

  if [[ ! -d "${dir}" ]]; then
    echo "Required directory missing: ${dir}" >&2
    exit 1
  fi

  if ! touch "${test_file}" 2>/dev/null; then
    echo "Directory is not writable: ${dir}" >&2
    echo "Fix LXC/storage read-write state before rerunning this script." >&2
    exit 1
  fi

  rm -f "${test_file}"
}

disable_startup_browser_setup() {
  local setup_files=()

  while IFS= read -r file; do
    setup_files+=("${file}")
  done < <(find "${NODE_PACKAGE_DIR}" -path "*/scripts/setup-browsers.*" -type f 2>/dev/null)

  if [[ "${#setup_files[@]}" -eq 0 ]]; then
    log "No setup-browsers script found; skipping startup setup patch"
    return
  fi

  for setup_file in "${setup_files[@]}"; do
    if grep -q "Browser setup skipped: managed by n8n-lxc repair script" "${setup_file}" 2>/dev/null; then
      log "Startup browser setup already patched: ${setup_file}"
      continue
    fi

    log "Patching startup browser setup: ${setup_file}"
    cp -n "${setup_file}" "${setup_file}.bak"
    printf "%s\n" "${SETUP_SKIP_CONTENT}" > "${setup_file}"
  done
}

systemctl stop n8n || true
systemctl reset-failed n8n || true

check_writable_dir "${APP_DIR}/custom"
check_writable_dir "/home/n8n"
disable_startup_browser_setup

log "Preparing Playwright browsers in ${NODE_BROWSERS_DIR}"
mkdir -p "${NODE_BROWSERS_DIR}"
chown n8n:n8n "${NODE_BROWSERS_DIR}"

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
    ln -sf ../chrome-linux64/chrome "${chromium_dir}/chrome-linux/chrome"
  fi
done

if ! find "${NODE_BROWSERS_DIR}" \( -path "*/chrome-linux/chrome" -type l -o -path "*/chrome-linux/chrome" -type f \) | grep -q .; then
  echo "Chromium exists, but expected chrome-linux/chrome was not created." >&2
  echo "Inspect: ${NODE_BROWSERS_DIR}/chromium-*/" >&2
  exit 1
fi

for firefox_dir in "${NODE_BROWSERS_DIR}"/firefox-*; do
  [[ -d "${firefox_dir}" ]] || continue
  if [[ -x "${firefox_dir}/firefox/firefox" && ! -e "${firefox_dir}/linux/firefox" ]]; then
    mkdir -p "${firefox_dir}/linux"
    ln -sf ../firefox/firefox "${firefox_dir}/linux/firefox"
  fi
done

for webkit_dir in "${NODE_BROWSERS_DIR}"/webkit-*; do
  [[ -d "${webkit_dir}" ]] || continue
  if [[ -x "${webkit_dir}/pw_run.sh" && ! -e "${webkit_dir}/webkit-1/minibrowser-gtk/pw_run.sh" ]]; then
    mkdir -p "${webkit_dir}/webkit-1/minibrowser-gtk"
    ln -sf ../../pw_run.sh "${webkit_dir}/webkit-1/minibrowser-gtk/pw_run.sh"
  fi
done

log "Installed browser executables:"
find "${NODE_BROWSERS_DIR}" -type f \( -name chrome -o -name firefox -o -name pw_run.sh \) -print
find "${NODE_BROWSERS_DIR}" -type l -print

log "Enabling and starting n8n"
systemctl enable n8n
systemctl start n8n
systemctl status n8n --no-pager

#!/usr/bin/env bash
set -euo pipefail

N8N_VERSION="${N8N_VERSION:-2.20.9}"
NPM_FETCH_RETRIES="${NPM_FETCH_RETRIES:-5}"
NPM_FETCH_RETRY_FACTOR="${NPM_FETCH_RETRY_FACTOR:-2}"
NPM_FETCH_RETRY_MINTIMEOUT="${NPM_FETCH_RETRY_MINTIMEOUT:-20000}"
NPM_FETCH_RETRY_MAXTIMEOUT="${NPM_FETCH_RETRY_MAXTIMEOUT:-120000}"
NPM_FETCH_TIMEOUT="${NPM_FETCH_TIMEOUT:-300000}"
APP_DIR="/opt/n8n"
BROWSERS_DIR="/home/n8n/.cache/ms-playwright"
ENV_DIR="/etc/n8n"
ENV_FILE="${ENV_DIR}/n8n.env"
SERVICE_FILE="/etc/systemd/system/n8n.service"
JOURNALD_DROPIN="/etc/systemd/journald.conf.d/n8n-limits.conf"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERATED_DB_PASSWORD=""

log() {
  printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root: sudo bash scripts/install.sh"
    exit 1
  fi
}

load_existing_env() {
  if [[ -f "${ENV_FILE}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
  fi
}

assert_rootfs_writable() {
  if findmnt -no OPTIONS / | grep -qw ro; then
    echo "Root filesystem is mounted read-only. Fix the LXC disk/filesystem before installing."
    exit 1
  fi

  if ! touch /tmp/n8n-install-write-test 2>/dev/null; then
    echo "Filesystem write test failed. Fix the LXC disk/filesystem before installing."
    exit 1
  fi

  rm -f /tmp/n8n-install-write-test
}

install_base_packages() {
  log "Installing base packages"
  if ! apt-get update; then
    log "apt update failed; clearing package lists and retrying once"
    rm -rf /var/lib/apt/lists/*
    mkdir -p /var/lib/apt/lists/partial
    apt-get update
  fi

  apt-get install -y curl ca-certificates gnupg build-essential postgresql postgresql-contrib openssl sudo git
}

install_playwright_system_packages() {
  log "Installing Playwright system packages"
  apt-get update
  apt-get install -y \
    libxcursor1 \
    libpangocairo-1.0-0 \
    libcairo-gobject2 \
    libgdk-pixbuf-2.0-0

  if apt-cache show libgtk-3-0t64 >/dev/null 2>&1; then
    apt-get install -y libgtk-3-0t64
  else
    apt-get install -y libgtk-3-0
  fi
}

install_nodejs() {
  if command -v node >/dev/null 2>&1 && node --version | grep -Eq '^v22\.'; then
    verify_npm_or_reinstall
    return
  fi

  log "Installing Node.js 22 from NodeSource"
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
  verify_npm_or_reinstall
}

verify_npm_or_reinstall() {
  if npm --version >/dev/null 2>&1 && node -e "require('/usr/lib/node_modules/npm/node_modules/promise-retry')" >/dev/null 2>&1; then
    configure_npm_network
    return
  fi

  log "npm is missing or corrupted; reinstalling NodeSource nodejs package"
  apt-get install --reinstall -y nodejs
  hash -r

  if ! npm --version >/dev/null 2>&1; then
    echo "npm is still unavailable after reinstalling nodejs"
    exit 1
  fi

  configure_npm_network
}

configure_npm_network() {
  log "Configuring npm network retry settings"
  npm config set fetch-retries "${NPM_FETCH_RETRIES}"
  npm config set fetch-retry-factor "${NPM_FETCH_RETRY_FACTOR}"
  npm config set fetch-retry-mintimeout "${NPM_FETCH_RETRY_MINTIMEOUT}"
  npm config set fetch-retry-maxtimeout "${NPM_FETCH_RETRY_MAXTIMEOUT}"
  npm config set fetch-timeout "${NPM_FETCH_TIMEOUT}"
  npm config set audit false
  npm config set fund false
}

npm_install_with_retry() {
  local attempt=1

  while true; do
    log "npm install attempt ${attempt}: npm install $*"
    if npm install \
      --fetch-retries="${NPM_FETCH_RETRIES}" \
      --fetch-retry-factor="${NPM_FETCH_RETRY_FACTOR}" \
      --fetch-retry-mintimeout="${NPM_FETCH_RETRY_MINTIMEOUT}" \
      --fetch-retry-maxtimeout="${NPM_FETCH_RETRY_MAXTIMEOUT}" \
      --fetch-timeout="${NPM_FETCH_TIMEOUT}" \
      --no-audit \
      --no-fund \
      "$@"; then
      return
    fi

    if [[ "${attempt}" -ge 3 ]]; then
      echo "npm install failed after ${attempt} attempts"
      exit 1
    fi

    attempt=$((attempt + 1))
    npm cache verify || true
    sleep 10
  done
}

clean_stale_global_n8n_install() {
  log "Cleaning stale global n8n install artifacts"
  npm uninstall -g n8n >/dev/null 2>&1 || true
  rm -rf /usr/lib/node_modules/.n8n-* /usr/local/lib/node_modules/.n8n-*
}

create_user_and_dirs() {
  if ! id n8n >/dev/null 2>&1; then
    useradd --system --create-home --home-dir /home/n8n --shell /usr/sbin/nologin n8n
  fi

  mkdir -p "${APP_DIR}/custom" "${APP_DIR}/backups" "${BROWSERS_DIR}" "${ENV_DIR}" /opt/obsidian-vault /opt/n8n-backup
  chown -R n8n:n8n "${APP_DIR}" /home/n8n
  chown root:n8n "${ENV_DIR}"
  chmod 750 "${ENV_DIR}"
}

install_n8n_and_browser_packages() {
  log "Installing n8n ${N8N_VERSION}"
  clean_stale_global_n8n_install
  npm_install_with_retry -g "n8n@${N8N_VERSION}"
  log "Installing Playwright packages and n8n community node"
  npm_install_with_retry --prefix "${APP_DIR}/custom" playwright playwright-core n8n-nodes-playwright
  chown -R n8n:n8n "${APP_DIR}"
  install_playwright_system_packages
  npx --prefix "${APP_DIR}/custom" playwright install-deps
  sudo -H -u n8n env PLAYWRIGHT_BROWSERS_PATH="${BROWSERS_DIR}" bash -lc "cd '${APP_DIR}/custom' && npx playwright install chromium firefox webkit"
}

configure_postgres() {
  log "Configuring PostgreSQL"
  systemctl enable --now postgresql
  local db_password="${DB_POSTGRESDB_PASSWORD:-}"

  if [[ -z "${db_password}" || "${db_password}" == replace_with_* ]]; then
    GENERATED_DB_PASSWORD="$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-32)"
    db_password="${GENERATED_DB_PASSWORD}"
  fi

  if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='n8n'" | grep -q 1; then
    sudo -u postgres psql -v ON_ERROR_STOP=1 -c "CREATE USER n8n WITH PASSWORD '${db_password}';"
  else
    sudo -u postgres psql -v ON_ERROR_STOP=1 -c "ALTER USER n8n WITH PASSWORD '${db_password}';"
  fi

  if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='n8n'" | grep -q 1; then
    sudo -u postgres createdb -O n8n n8n
  fi
}

write_env_file() {
  if [[ -f "${ENV_FILE}" ]]; then
    chown root:n8n "${ENV_DIR}" "${ENV_FILE}"
    chmod 750 "${ENV_DIR}"
    chmod 640 "${ENV_FILE}"

    if grep -q '^PLAYWRIGHT_BROWSERS_PATH=/opt/n8n/ms-playwright$' "${ENV_FILE}"; then
      log "Updating existing PLAYWRIGHT_BROWSERS_PATH for n8n-nodes-playwright compatibility"
      sed -i 's#^PLAYWRIGHT_BROWSERS_PATH=/opt/n8n/ms-playwright$#PLAYWRIGHT_BROWSERS_PATH=/home/n8n/.cache/ms-playwright#' "${ENV_FILE}"
    fi

    echo "Keeping existing ${ENV_FILE}"
    return
  fi

  local encryption_key
  local db_password
  encryption_key="$(openssl rand -hex 32)"
  db_password="${GENERATED_DB_PASSWORD:-$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-32)}"

  sed \
    -e "s/N8N_VERSION=.*/N8N_VERSION=${N8N_VERSION}/" \
    -e "s/N8N_ENCRYPTION_KEY=.*/N8N_ENCRYPTION_KEY=${encryption_key}/" \
    -e "s/DB_POSTGRESDB_PASSWORD=.*/DB_POSTGRESDB_PASSWORD=${db_password}/" \
    "${REPO_DIR}/.env.example" > "${ENV_FILE}"

  chown root:n8n "${ENV_FILE}"
  chmod 640 "${ENV_FILE}"
  echo "Created ${ENV_FILE}. Edit Supabase and Browserless secrets before production use."
}

configure_journald() {
  log "Configuring journald limits"
  mkdir -p "$(dirname "${JOURNALD_DROPIN}")"
  cat > "${JOURNALD_DROPIN}" <<'EOF'
[Journal]
SystemMaxUse=500M
RuntimeMaxUse=200M
EOF
  systemctl restart systemd-journald
}

install_service() {
  log "Installing n8n systemd service"
  cp "${REPO_DIR}/execution-hooks.js" "${APP_DIR}/execution-hooks.js"
  cp "${REPO_DIR}/systemd/n8n.service" "${SERVICE_FILE}"
  chown n8n:n8n "${APP_DIR}/execution-hooks.js"
  chmod 644 "${APP_DIR}/execution-hooks.js" "${SERVICE_FILE}"

  systemctl daemon-reload
  systemctl enable n8n
}

main() {
  require_root
  load_existing_env
  assert_rootfs_writable
  install_base_packages
  install_nodejs
  create_user_and_dirs
  install_n8n_and_browser_packages
  configure_postgres
  write_env_file
  configure_journald
  install_service
  echo "Install complete. Edit ${ENV_FILE}, then run: sudo systemctl restart n8n"
}

main "$@"

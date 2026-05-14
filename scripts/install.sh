#!/usr/bin/env bash
set -euo pipefail

N8N_VERSION="${N8N_VERSION:-2.19.4}"
NPM_FETCH_RETRIES="${NPM_FETCH_RETRIES:-5}"
NPM_FETCH_RETRY_FACTOR="${NPM_FETCH_RETRY_FACTOR:-2}"
NPM_FETCH_RETRY_MINTIMEOUT="${NPM_FETCH_RETRY_MINTIMEOUT:-20000}"
NPM_FETCH_RETRY_MAXTIMEOUT="${NPM_FETCH_RETRY_MAXTIMEOUT:-120000}"
NPM_FETCH_TIMEOUT="${NPM_FETCH_TIMEOUT:-300000}"
APP_DIR="/opt/n8n"
ENV_DIR="/etc/n8n"
ENV_FILE="${ENV_DIR}/n8n.env"
SERVICE_FILE="/etc/systemd/system/n8n.service"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() {
  printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root: sudo bash scripts/install.sh"
    exit 1
  fi
}

install_base_packages() {
  log "Installing base packages"
  apt-get update
  apt-get install -y curl ca-certificates gnupg build-essential postgresql postgresql-contrib openssl sudo git
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

create_user_and_dirs() {
  if ! id n8n >/dev/null 2>&1; then
    useradd --system --create-home --home-dir /home/n8n --shell /usr/sbin/nologin n8n
  fi

  mkdir -p "${APP_DIR}/custom" "${APP_DIR}/backups" "${APP_DIR}/ms-playwright" "${ENV_DIR}" /opt/obsidian-vault /opt/n8n-backup
  chown -R n8n:n8n "${APP_DIR}" /home/n8n
  chmod 750 "${ENV_DIR}"
}

install_n8n_and_browser_packages() {
  log "Installing n8n ${N8N_VERSION}"
  npm_install_with_retry -g "n8n@${N8N_VERSION}"
  log "Installing Playwright packages and n8n community node"
  npm_install_with_retry --prefix "${APP_DIR}/custom" playwright playwright-core n8n-nodes-playwright
  chown -R n8n:n8n "${APP_DIR}"
  npx --prefix "${APP_DIR}/custom" playwright install-deps chromium
  sudo -H -u n8n env PLAYWRIGHT_BROWSERS_PATH="${APP_DIR}/ms-playwright" bash -lc "cd '${APP_DIR}/custom' && npx playwright install chromium"
}

configure_postgres() {
  log "Configuring PostgreSQL"
  systemctl enable --now postgresql

  if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='n8n'" | grep -q 1; then
    sudo -u postgres psql -c "CREATE USER n8n WITH PASSWORD 'n8n_change_me';"
  fi

  if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='n8n'" | grep -q 1; then
    sudo -u postgres createdb -O n8n n8n
  fi
}

write_env_file() {
  if [[ -f "${ENV_FILE}" ]]; then
    echo "Keeping existing ${ENV_FILE}"
    return
  fi

  local encryption_key
  local db_password
  encryption_key="$(openssl rand -hex 32)"
  db_password="$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-32)"

  sudo -u postgres psql -c "ALTER USER n8n WITH PASSWORD '${db_password}';"

  sed \
    -e "s/N8N_VERSION=.*/N8N_VERSION=${N8N_VERSION}/" \
    -e "s/N8N_ENCRYPTION_KEY=.*/N8N_ENCRYPTION_KEY=${encryption_key}/" \
    -e "s/DB_POSTGRESDB_PASSWORD=.*/DB_POSTGRESDB_PASSWORD=${db_password}/" \
    "${REPO_DIR}/.env.example" > "${ENV_FILE}"

  chown root:n8n "${ENV_FILE}"
  chmod 640 "${ENV_FILE}"
  echo "Created ${ENV_FILE}. Edit Supabase and Browserless secrets before production use."
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
  install_base_packages
  install_nodejs
  create_user_and_dirs
  install_n8n_and_browser_packages
  configure_postgres
  write_env_file
  install_service
  echo "Install complete. Edit ${ENV_FILE}, then run: sudo systemctl restart n8n"
}

main "$@"

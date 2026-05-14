#!/usr/bin/env bash
set -euo pipefail

N8N_VERSION="${N8N_VERSION:-2.19.4}"
APP_DIR="/opt/n8n"
ENV_DIR="/etc/n8n"
ENV_FILE="${ENV_DIR}/n8n.env"
SERVICE_FILE="/etc/systemd/system/n8n.service"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root: sudo bash scripts/install.sh"
    exit 1
  fi
}

install_base_packages() {
  apt-get update
  apt-get install -y curl ca-certificates gnupg build-essential postgresql postgresql-contrib openssl sudo
}

install_nodejs() {
  if command -v node >/dev/null 2>&1 && node --version | grep -Eq '^v22\.'; then
    return
  fi

  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
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
  npm install -g "n8n@${N8N_VERSION}"
  npm install --prefix "${APP_DIR}/custom" playwright playwright-core n8n-nodes-playwright
  chown -R n8n:n8n "${APP_DIR}"
  npx --prefix "${APP_DIR}/custom" playwright install-deps chromium
  sudo -H -u n8n env PLAYWRIGHT_BROWSERS_PATH="${APP_DIR}/ms-playwright" npx --prefix "${APP_DIR}/custom" playwright install chromium
}

configure_postgres() {
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

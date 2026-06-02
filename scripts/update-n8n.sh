#!/usr/bin/env bash
set -euo pipefail

NPM_FETCH_RETRIES="${NPM_FETCH_RETRIES:-5}"
NPM_FETCH_RETRY_FACTOR="${NPM_FETCH_RETRY_FACTOR:-2}"
NPM_FETCH_RETRY_MINTIMEOUT="${NPM_FETCH_RETRY_MINTIMEOUT:-20000}"
NPM_FETCH_RETRY_MAXTIMEOUT="${NPM_FETCH_RETRY_MAXTIMEOUT:-120000}"
NPM_FETCH_TIMEOUT="${NPM_FETCH_TIMEOUT:-300000}"
APP_DIR="/opt/n8n"
ENV_FILE="/etc/n8n/n8n.env"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_VERSION="${N8N_VERSION:-}"
SKIP_BACKUP="${SKIP_BACKUP:-0}"
RUN_VERIFY="${RUN_VERIFY:-1}"
UPDATE_ENV_VERSION="${UPDATE_ENV_VERSION:-1}"

log() {
  printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root: sudo bash scripts/update-n8n.sh"
    exit 1
  fi
}

configure_npm_network() {
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

resolve_target_version() {
  if [[ -n "${TARGET_VERSION}" && "${TARGET_VERSION}" != "latest" ]]; then
    return
  fi

  log "Resolving latest stable n8n version from npm"
  TARGET_VERSION="$(npm view n8n version)"
}

update_env_version() {
  [[ "${UPDATE_ENV_VERSION}" == "1" ]] || return
  [[ -f "${ENV_FILE}" ]] || return

  if grep -q '^N8N_VERSION=' "${ENV_FILE}"; then
    sed -i "s/^N8N_VERSION=.*/N8N_VERSION=${TARGET_VERSION}/" "${ENV_FILE}"
  else
    printf '\nN8N_VERSION=%s\n' "${TARGET_VERSION}" >> "${ENV_FILE}"
  fi
}

install_hooks() {
  if [[ -f "${REPO_DIR}/execution-hooks.js" ]]; then
    install -m 0644 "${REPO_DIR}/execution-hooks.js" "${APP_DIR}/execution-hooks.js"
    chown n8n:n8n "${APP_DIR}/execution-hooks.js"
  fi
}

main() {
  require_root
  command -v node >/dev/null
  command -v npm >/dev/null
  configure_npm_network
  resolve_target_version

  local current_version=""
  current_version="$(n8n --version 2>/dev/null || true)"
  log "Current n8n version: ${current_version:-unknown}"
  log "Target n8n version: ${TARGET_VERSION}"

  if [[ "${SKIP_BACKUP}" != "1" ]]; then
    bash "${REPO_DIR}/scripts/backup.sh"
  fi

  systemctl stop n8n || true
  npm_install_with_retry -g "n8n@${TARGET_VERSION}"
  install_hooks
  update_env_version
  systemctl daemon-reload
  systemctl start n8n

  log "Updated n8n version: $(n8n --version)"
  systemctl status n8n --no-pager

  if [[ "${RUN_VERIFY}" == "1" ]]; then
    bash "${REPO_DIR}/scripts/verify.sh"
  fi
}

main "$@"

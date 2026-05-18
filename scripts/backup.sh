#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/opt/n8n/backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
STAMP="$(date +%Y%m%d-%H%M%S)"
TARGET_DIR="${BACKUP_DIR}/${STAMP}"
ENV_FILE="/etc/n8n/n8n.env"

trap 'echo "BACKUP FAILED at line ${LINENO}" >&2' ERR

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

make_backup_dir() {
  mkdir -p "${TARGET_DIR}"
  chown n8n:n8n "${TARGET_DIR}"
}

fix_env_permissions() {
  if [[ -f "${ENV_FILE}" ]]; then
    chown root:n8n "$(dirname "${ENV_FILE}")" "${ENV_FILE}"
    chmod 750 "$(dirname "${ENV_FILE}")"
    chmod 640 "${ENV_FILE}"
  fi
}

export_n8n_data() {
  if ! command -v n8n >/dev/null 2>&1; then
    echo "n8n binary is missing. Reinstall n8n before exporting workflows or credentials."
    exit 1
  fi

  local n8n_env=(
    "N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY:-}"
    "DB_TYPE=${DB_TYPE:-postgresdb}"
    "DB_POSTGRESDB_HOST=${DB_POSTGRESDB_HOST:-127.0.0.1}"
    "DB_POSTGRESDB_PORT=${DB_POSTGRESDB_PORT:-5432}"
    "DB_POSTGRESDB_DATABASE=${DB_POSTGRESDB_DATABASE:-n8n}"
    "DB_POSTGRESDB_USER=${DB_POSTGRESDB_USER:-n8n}"
    "DB_POSTGRESDB_PASSWORD=${DB_POSTGRESDB_PASSWORD:-}"
  )

  sudo -H -u n8n env "${n8n_env[@]}" n8n export:workflow --all --output="${TARGET_DIR}/workflows.json"
  sudo -H -u n8n env "${n8n_env[@]}" n8n export:credentials --all --decrypted --output="${TARGET_DIR}/credentials.decrypted.json"
  chmod 600 "${TARGET_DIR}/credentials.decrypted.json"
}

dump_postgres() {
  PGPASSWORD="${DB_POSTGRESDB_PASSWORD}" pg_dump \
    --host="${DB_POSTGRESDB_HOST:-127.0.0.1}" \
    --port="${DB_POSTGRESDB_PORT:-5432}" \
    --username="${DB_POSTGRESDB_USER:-n8n}" \
    --dbname="${DB_POSTGRESDB_DATABASE:-n8n}" \
    --format=custom \
    --file="${TARGET_DIR}/n8n-db.dump"
}

rotate_backups() {
  find "${BACKUP_DIR}" -mindepth 1 -maxdepth 1 -type d -mtime +"${BACKUP_RETENTION_DAYS}" -exec rm -rf {} +
}

main() {
  load_env
  fix_env_permissions
  make_backup_dir
  export_n8n_data
  dump_postgres
  rotate_backups
  echo "Backup written to ${TARGET_DIR}"
}

main "$@"

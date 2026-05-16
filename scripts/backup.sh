#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/opt/n8n/backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
STAMP="$(date +%Y%m%d-%H%M%S)"
TARGET_DIR="${BACKUP_DIR}/${STAMP}"
ENV_FILE="/etc/n8n/n8n.env"

trap 'echo "BACKUP FAILED at line ${LINENO}" >&2' ERR

load_env() {
  if [[ -f "${ENV_FILE}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
  fi
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

  sudo -H -u n8n bash -lc "set -a; source '${ENV_FILE}'; set +a; n8n export:workflow --all --output='${TARGET_DIR}/workflows.json'"
  sudo -H -u n8n bash -lc "set -a; source '${ENV_FILE}'; set +a; n8n export:credentials --all --decrypted --output='${TARGET_DIR}/credentials.decrypted.json'"
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

#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/opt/n8n/backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"
TARGET_DIR="${BACKUP_DIR}/${STAMP}"
ENV_FILE="/etc/n8n/n8n.env"

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

export_n8n_data() {
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

main() {
  load_env
  make_backup_dir
  export_n8n_data
  dump_postgres
  echo "Backup written to ${TARGET_DIR}"
}

main "$@"

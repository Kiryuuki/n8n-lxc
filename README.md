# n8n LXC Bare-Metal Install

Ubuntu 22.04 direct install for n8n with systemd, local PostgreSQL, Supabase execution logging, local Playwright/Chromium, and Browserless support. No Docker.

## What This Provides

- n8n installed globally with npm and pinned by `N8N_VERSION`
- local PostgreSQL database for n8n
- `systemd` service at `/etc/systemd/system/n8n.service`
- backend hook at `/opt/n8n/execution-hooks.js`
- runtime env at `/etc/n8n/n8n.env`
- local Playwright Chromium under `/opt/n8n/ms-playwright`
- Browserless CDP connection through `BROWSERLESS_WS_URL`

## Security Notes

Rotate the Supabase service role key that was pasted in chat before using this repo. Do not commit `.env`, real service keys, exported credentials, or database dumps.

`N8N_ENABLE_EXECUTE_COMMAND=true` is enabled for Windows parity. This lets n8n run shell commands on the host. Keep the instance private, admin-only, and protected by network controls.

## Files

```text
.
├── .env.example
├── .gitignore
├── execution-hooks.js
├── supabase_migration.sql
├── docs/
│   └── windows-to-lxc.md
├── scripts/
│   ├── backup.sh
│   ├── install.sh
│   └── verify.sh
└── systemd/
    └── n8n.service
```

## Install

On the Ubuntu 22.04 LXC:

```bash
sudo apt-get update
sudo apt-get install -y git
git clone <repo-url> n8n-lxc
cd n8n-lxc
sudo bash scripts/install.sh
```

Edit secrets and public URLs:

```bash
sudo nano /etc/n8n/n8n.env
```

Required edits:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_KEY`
- `BROWSERLESS_WS_URL`
- `WEBHOOK_URL`
- `N8N_HOST`
- `N8N_EDITOR_BASE_URL`
- `N8N_ENCRYPTION_KEY` if migrating credentials from Windows

Start n8n:

```bash
sudo systemctl restart n8n
sudo systemctl status n8n
```

## Supabase Migration

Run `supabase_migration.sql` in the Supabase SQL editor before expecting hook inserts.

The hook writes:

- `execution_id`
- `workflow_id`
- `workflow_name`
- `status`
- `started_at`
- `finished_at`
- `duration_ms`
- `mode`

It does not write workflow input/output.

## Verify

```bash
sudo bash scripts/verify.sh
```

Manual checks:

```bash
journalctl -u n8n -n 100 --no-pager
curl http://127.0.0.1:5678/healthz || curl http://127.0.0.1:5678
```

Expected journal line:

```text
[HOOK] n8n IS READY AND HOOKS ARE ACTIVE
```

Run one manual workflow, then confirm Supabase has a row in `n8n_execution_logs`.

## Backup

```bash
sudo bash scripts/backup.sh
```

Backups are written to `/opt/n8n/backups/<timestamp>/`:

- `workflows.json`
- `credentials.decrypted.json`
- `n8n-db.dump`

Treat `credentials.decrypted.json` as a secret.

## Upgrade n8n

Change version for one install run:

```bash
sudo N8N_VERSION=2.19.4 bash scripts/install.sh
sudo systemctl restart n8n
```

Use a known-good version. n8n releases often; test before upgrading production.

## Rollback

```bash
sudo npm install -g n8n@<previous-version>
sudo systemctl restart n8n
```

Restore database if needed:

```bash
sudo systemctl stop n8n
PGPASSWORD='<db-password>' pg_restore --clean --if-exists \
  --host=127.0.0.1 --username=n8n --dbname=n8n /opt/n8n/backups/<timestamp>/n8n-db.dump
sudo systemctl start n8n
```

## Troubleshooting

Hook not loaded:

```bash
grep EXTERNAL_HOOK_FILES /etc/n8n/n8n.env
journalctl -u n8n -n 100 --no-pager
```

Supabase insert rejected:

```bash
journalctl -u n8n -n 200 --no-pager | grep SUPABASE
```

Postgres connection failed:

```bash
systemctl status postgresql
sudo -u postgres psql -c "\l"
```

Playwright failed:

```bash
sudo -H -u n8n env PLAYWRIGHT_BROWSERS_PATH=/opt/n8n/ms-playwright \
  npx --prefix /opt/n8n/custom playwright install chromium
```

## Related

- [n8n npm install](https://docs.n8n.io/hosting/installation/npm/)
- [n8n external hooks](https://docs.n8n.io/hosting/configuration/external-hooks/)
- [n8n configuration methods](https://docs.n8n.io/hosting/configuration/configuration-methods/)

— Dash

# n8n LXC Bare-Metal Install

Ubuntu 22.04 direct install for n8n with systemd, local PostgreSQL, Supabase execution logging, local Playwright/Chromium, and Browserless support. No Docker.

## 🚀 Quick Start & Installation

Get your bare-metal n8n runtime up and running on an Ubuntu 22.04 LXC in a few simple steps.

> [!IMPORTANT]
> Ensure your target LXC has **systemd** enabled, at least **2 CPU cores**, **2 GB RAM**, and outbound internet access before starting.

### 1. One-Line Installation

Execute the following command to update packages, install git, clone this repository, and run the automated installation script:

```bash
sudo apt-get update && sudo apt-get install -y git && git clone https://github.com/Kiryuuki/n8n-lxc.git && cd n8n-lxc && sudo bash scripts/install.sh
```

This automated script will:
- Install system dependencies, Node.js 22 LTS, and PostgreSQL.
- Pin and install `n8n` globally.
- Install Playwright (Chromium, Firefox, WebKit) and the community Playwright node.
- Configure local PostgreSQL with generated secure credentials.
- Create `/etc/n8n/n8n.env` with custom secrets (such as the encryption key).
- Enable and configure the systemd service with automated hardening.
- Set up a customized login MOTD banner with helpful commands.

### 2. Configure the Environment

You **must** configure your environment settings before starting production. Create the directory and open the configuration file:

```bash
sudo mkdir -p /etc/n8n && sudo nano /etc/n8n/n8n.env
```

At a minimum, configure the following variables:
- `WEBHOOK_URL` (e.g. `https://n8n.example.com`)
- `N8N_HOST` & `N8N_EDITOR_BASE_URL`
- `SUPABASE_URL` & `SUPABASE_SERVICE_KEY` (if utilizing Supabase execution logging)
- `BROWSERLESS_WS_URL` (if using external Browserless support)

> [!TIP]
> If migrating from an existing Windows n8n setup, copy your original `N8N_ENCRYPTION_KEY` into this file so your imported credentials decrypt correctly. See the [Windows Migration Guide](docs/windows-to-lxc.md) for details.

### 3. Restart and Verify

Apply your custom environment configuration and check your installation status:

```bash
# Restart the n8n service to apply env changes
sudo systemctl restart n8n

# Run the validation suite to verify all components
sudo bash scripts/verify.sh
```

The validation suite verifies Node.js, PostgreSQL, systemd status, Playwright/Chromium execution, and external Browserless connectivity.

## Features

- Bare-metal n8n install for Ubuntu LXC, pinned to a known `N8N_VERSION`.
- systemd service with restart policy, env-file loading, and baseline hardening.
- Local PostgreSQL setup with generated credentials and persistent n8n data.
- Supabase execution hooks for external workflow run logging and startup health pings.
- Local Playwright browser support with Chromium, Firefox, WebKit, and compatibility repair tooling.
- Browserless CDP support for remote headless scraping without hardcoded workflow tokens.
- Secret-safe runtime config through `/etc/n8n/n8n.env` and tracked `.env.example` placeholders.
- Backup script with workflow export, decrypted credential export, Postgres dump, error trap, and retention.
- Verification script for Node, npm, n8n, Postgres, service health, Playwright, Browserless, and hooks.
- Login MOTD command banner for quick n8n operations inside the LXC shell.
- Recovery helpers for npm install failures, corrupted Playwright paths, read-only LXC storage, and stale global n8n installs.
- Journald log size limits and GitHub Actions shellcheck for basic script quality.

## What This Project Is For

This repository builds a production-ready n8n server inside a dedicated Ubuntu LXC. It is for running client-grade automations that need reliable uptime, browser automation, execution logs, local backups, and a clean migration path from a Windows-hosted n8n setup.

## What It Solves

- Moves n8n out of a desktop-dependent Windows setup and into a persistent Linux service.
- Gives n8n a dedicated PostgreSQL database instead of relying on fragile local app state.
- Adds Supabase execution logging so workflow runs can be audited outside the n8n UI.
- Supports both local Playwright browser execution and Browserless CDP for remote headless scraping.
- Provides repair and verification scripts for the common failure points: npm interruption, Playwright browser paths, Browserless connectivity, hooks, and service startup.
- Keeps secrets in `/etc/n8n/n8n.env` and out of git.

## Why We Built It

The goal is confidence: automations should survive restarts, expose failures, and leave evidence that they ran. This LXC setup turns n8n from a local workflow builder into a maintainable automation runtime that can support real client work, portfolio demos, scraping jobs, AI workflows, and long-running scheduled systems.

## Requirements

Target host:

- Ubuntu 22.04 LXC
- root or sudo access
- systemd enabled in the LXC
- outbound internet access for apt, NodeSource, npm, and Playwright browser downloads
- at least 2 CPU cores, 2 GB RAM, and 10 GB disk
- port `5678` reachable from your reverse proxy or tunnel

External services:

- Supabase project for execution logs
- Browserless WebSocket endpoint, for example `ws://browserless.example.internal:3000`
- Public n8n URL from Cloudflare Tunnel, Caddy, Nginx, or another reverse proxy

Secrets you need before production:

- rotated Supabase service role key
- n8n encryption key from the old Windows instance if migrating credentials
- Browserless token
- Postgres password generated by the installer or your own replacement

## Installed Dependencies

`scripts/install.sh` installs and configures:

- `curl`
- `ca-certificates`
- `gnupg`
- `build-essential`
- `postgresql`
- `postgresql-contrib`
- `openssl`
- `sudo`
- `netcat-openbsd`
- Node.js 22 LTS from NodeSource
- n8n npm package, pinned by `N8N_VERSION`
- npm retry and timeout settings for unstable network installs
- `playwright`
- `playwright-core`
- `n8n-nodes-playwright`
- Chromium, Firefox, and WebKit browser binaries for the `n8n` user
- Playwright Linux system dependencies
- GTK/Cairo packages required by `n8n-nodes-playwright` startup validation
- `n8n` system user
- `/opt/n8n`
- `/etc/n8n/n8n.env`
- `/etc/systemd/system/n8n.service`

## Repository Layout

```text
.
|-- .env.example
|-- .gitignore
|-- README.md
|-- execution-hooks.js
|-- supabase_migration.sql
|-- docs/
|   |-- browserless-custom-script.md
|   `-- windows-to-lxc.md
|-- motd/
|   `-- 99-n8n-lxc
|-- scripts/
|   |-- backup.sh
|   |-- install.sh
|   |-- browserless-smoke.js
|   |-- repair-playwright-node.sh
|   `-- verify.sh
`-- systemd/
    `-- n8n.service
```

## If npm Install Was Interrupted

If the first install died with `ECONNRESET` and npm now fails with `Cannot find module 'promise-retry'`, repair NodeSource npm first:

```bash
sudo apt-get update
sudo apt-get install --reinstall -y nodejs
hash -r
npm --version
```

Then pull the latest installer and rerun:

```bash
git pull
sudo bash scripts/install.sh
```

Do not run `npm install -g npm@latest` as the recovery step. Use the NodeSource `nodejs` package reinstall so npm's bundled files are restored together.

## Configure Environment

Edit (creating the parent directory first if it doesn't already exist):

```bash
sudo mkdir -p /etc/n8n && sudo nano /etc/n8n/n8n.env
```

Required production values:

```env
N8N_VERSION=2.20.9
WEBHOOK_URL=https://n8n.example.com
N8N_HOST=n8n.example.com
N8N_EDITOR_BASE_URL=https://n8n.example.com
N8N_CORS_ALLOWED_ORIGINS=https://n8n.example.com,https://claude.ai,https://claude.com
N8N_CORS_ALLOW_CREDENTIALS=true
N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_KEY=replace_with_rotated_supabase_key
BROWSERLESS_WS_URL='ws://browserless.example.internal:3000?token=replace_with_token&timeout=55000'
```

If migrating from Windows n8n, replace the generated `N8N_ENCRYPTION_KEY` with the exact old key before importing credentials.

Keep these values:

```env
EXTERNAL_HOOK_FILES=/opt/n8n/execution-hooks.js
N8N_CUSTOM_EXTENSIONS=/opt/n8n/custom
NODE_PATH=/opt/n8n/custom/node_modules
NODE_FUNCTION_ALLOW_EXTERNAL=playwright,playwright-core
NODE_FUNCTION_ALLOW_BUILTIN=*
N8N_BLOCK_ENV_ACCESS_IN_NODE=false
# High-risk: enables shell command execution from workflows. Enable only on private/admin-only instances.
N8N_ENABLE_EXECUTE_COMMAND=false
```

Set `N8N_ENABLE_EXECUTE_COMMAND=true` only if you need Execute Command workflows. Keep that mode private, admin-only, and behind trusted network controls.

## Supabase Setup

Run `supabase_migration.sql` in the Supabase SQL editor before expecting hook inserts.

The hook writes only execution metadata:

- `execution_id`
- `workflow_id`
- `workflow_name`
- `status`
- `started_at`
- `finished_at`
- `duration_ms`
- `mode`

It does not write raw workflow input, output, node data, or PII.

## Start n8n

```bash
sudo systemctl restart n8n
sudo systemctl status n8n
```

Follow logs:

```bash
journalctl -u n8n -f
```

Expected hook line:

```text
[HOOK] n8n IS READY AND HOOKS ARE ACTIVE
[HOOK] Supabase ping: OK
```

## Verify Install

Run:

```bash
sudo bash scripts/verify.sh
```

The verifier checks:

- Node.js 22
- npm
- n8n binary
- PostgreSQL service
- n8n systemd service
- `/etc/n8n/n8n.env`
- `/opt/n8n/execution-hooks.js`
- local n8n HTTP endpoint
- local Playwright Chromium launch
- Browserless CDP connection when `BROWSERLESS_WS_URL` is configured
- hook loaded in `journalctl`

Manual health check:

```bash
curl http://127.0.0.1:5678/healthz || curl http://127.0.0.1:5678
```

Final production check:

1. Run one manual n8n workflow.
2. Confirm `journalctl -u n8n -n 100 --no-pager` shows hook success.
3. Confirm Supabase has a startup row with `workflow_name = '__hook_healthcheck'` and `status = 'success'`.
4. Confirm Supabase has a workflow execution row in `n8n_execution_logs`.

Supabase SQL check:

```sql
select created_at, execution_id, workflow_name, status, mode
from n8n_execution_logs
order by created_at desc
limit 10;
```

## Browserless Usage in n8n Playwright Node

Use this pattern inside the n8n Playwright node:

```javascript
const browser = await $playwright.chromium.connectOverCDP(
  $env.BROWSERLESS_WS_URL
);
```

Equivalent concrete URL shape:

```text
ws://browserless.example.internal:3000?token=replace_with_token&timeout=55000
```

If the community Playwright node fails before the custom script runs with a missing local browser path, use the Code node or Execute Command fallback in [docs/browserless-custom-script.md](docs/browserless-custom-script.md). Browserless itself does not need local Chromium; the failure is the community node's local browser validation.

## Backup

```bash
sudo bash scripts/backup.sh
```

Backups are written to:

```text
/opt/n8n/backups/<timestamp>/
```

Backups older than 7 days are removed by default. Override with `BACKUP_RETENTION_DAYS=<days>`.

Files:

- `workflows.json`
- `credentials.decrypted.json`
- `n8n-db.dump`

Treat `credentials.decrypted.json` as a secret.

## Migration From Windows

Export from Windows:

```bash
n8n export:workflow --all --output=workflows.json
n8n export:credentials --all --decrypted --output=credentials.json
```

Copy exports to the LXC, then import:

```bash
sudo -H -u n8n n8n import:workflow --input=/path/to/workflows.json
sudo -H -u n8n n8n import:credentials --input=/path/to/credentials.json
sudo systemctl restart n8n
```

Credential import only works if `N8N_ENCRYPTION_KEY` matches the old Windows instance.

## Upgrade n8n

Test before production upgrade:

```bash
sudo bash scripts/backup.sh
sudo N8N_VERSION=2.20.9 bash scripts/install.sh
sudo systemctl restart n8n
sudo bash scripts/verify.sh
```

Use a known-good version. Do not blindly run latest on production.

## Rollback

Rollback n8n package:

```bash
sudo npm install -g n8n@<previous-version>
sudo systemctl restart n8n
```

Restore database if needed:

```bash
sudo systemctl stop n8n
PGPASSWORD='<db-password>' pg_restore --clean --if-exists \
  --host=127.0.0.1 \
  --username=n8n \
  --dbname=n8n \
  /opt/n8n/backups/<timestamp>/n8n-db.dump
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
sudo -u postgres psql -c "\du"
```

Playwright installation or runtime failed:

If the automated Playwright installation fails during the initial execution of `sudo bash scripts/install.sh` (e.g. due to interrupted network downloads, package locks, or strict LXC configurations), follow these recovery steps:

1. **Manually Install Missing System Packages**:
   Ensure all base OS dependencies for Playwright and Chromium are fully installed:
   ```bash
   sudo apt-get update
   sudo apt-get install -y libxcursor1 libpangocairo-1.0-0 libcairo-gobject2 libgdk-pixbuf-2.0-0
   sudo apt-get install -y libgtk-3-0t64 || sudo apt-get install -y libgtk-3-0
   ```

2. **Trigger Playwright Binary Installation Manually**:
   Install the required system dependencies and trigger the browser download as the dedicated `n8n` user:
   ```bash
   # Install dependencies (as root)
   sudo npx --prefix /opt/n8n/custom playwright install-deps

   # Download browser binaries (as n8n user)
   sudo -H -u n8n env PLAYWRIGHT_BROWSERS_PATH=/home/n8n/.cache/ms-playwright \
     npx --prefix /opt/n8n/custom playwright install chromium firefox webkit
   ```

3. **Resolve Path and Symlink Mismatches**:
   The `n8n-nodes-playwright` community node expects certain older directory patterns (like `chrome-linux/chrome` instead of newer `chrome-linux64/chrome`) and checks specific package-local paths. Apply our custom compatibility and patching script to align all symlinks and file permissions:
   ```bash
   sudo bash scripts/repair-playwright-node.sh
   ```

4. **Mark Playwright Cache as Complete**:
   To ensure the main installer script does not try to perform the slow browser downloads again, create the verification flag file:
   ```bash
   sudo mkdir -p /home/n8n/.cache/ms-playwright
   sudo touch /home/n8n/.cache/ms-playwright/.install-complete
   sudo chown -R n8n:n8n /home/n8n/.cache/ms-playwright
   ```

5. **Resume Automated Setup**:
   Once Playwright is fully verified, rerun the main installation script to complete any remaining steps (such as PostgreSQL setup or systemd configuration):
   ```bash
   sudo bash scripts/install.sh
   ```
   Thanks to the built-in cache check, the installer will automatically detect that Playwright is working and skip re-downloading!

Browserless failed:

```bash
grep BROWSERLESS_WS_URL /etc/n8n/n8n.env
sudo bash scripts/verify.sh
```

If Browserless times out, check the Browserless host from the LXC:

```bash
nc -vz browserless.example.internal 3000
curl -I http://browserless.example.internal:3000
```

Replace host and port with your real Browserless address. A timeout means the Browserless service is down, the port is wrong, or the LXC cannot route to that host.

n8n service failed:

```bash
systemctl status n8n
journalctl -u n8n -n 200 --no-pager
```

npm network abort during install:

```bash
sudo apt-get install --reinstall -y nodejs
npm config set fetch-retries 5
npm config set fetch-retry-mintimeout 20000
npm config set fetch-retry-maxtimeout 120000
npm config set fetch-timeout 300000
sudo bash scripts/install.sh
```

npm corrupted after interrupted install:

```bash
sudo apt-get install --reinstall -y nodejs
hash -r
npm --version
sudo bash scripts/install.sh
```

Playwright install fails with `spawn sh EACCES`:

```bash
git pull
sudo bash scripts/install.sh
```

This happens when the repo is cloned under `/root` and the installer switches to the `n8n` user before running Playwright. Current installer versions run Playwright from `/opt/n8n/custom`, which the `n8n` user can access.

`n8n-nodes-playwright` fails at service startup with missing browser cache:

```bash
git pull
sudo bash scripts/install.sh
grep PLAYWRIGHT_BROWSERS_PATH /etc/n8n/n8n.env
sudo systemctl restart n8n
```

Expected value:

```env
PLAYWRIGHT_BROWSERS_PATH=/home/n8n/.cache/ms-playwright
```

## Security Checklist

- Rotate the Supabase service key pasted in chat.
- Keep `.env` and `/etc/n8n/n8n.env` out of git.
- Do not commit workflow exports with credentials.
- Restrict access to n8n UI.
- Protect the Cloudflare tunnel/reverse proxy.
- Treat Execute Command node as admin-only.
- Review logs for PII before sharing.

## Related

- [n8n npm install](https://docs.n8n.io/hosting/installation/npm/)
- [n8n external hooks](https://docs.n8n.io/hosting/configuration/external-hooks/)
- [n8n configuration methods](https://docs.n8n.io/hosting/configuration/configuration-methods/)
- [Playwright browsers](https://playwright.dev/docs/browsers)

Dash

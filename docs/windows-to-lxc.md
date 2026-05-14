# Windows to Ubuntu LXC Mapping

This repo replaces the Windows batch launcher with a direct Ubuntu 22.04 install.

## Runtime

| Windows batch value | Ubuntu LXC value |
|---|---|
| `n8n start` in `cmd /k` | `systemd` service: `n8n.service` |
| inline `set` variables | `/etc/n8n/n8n.env` |
| `WEBHOOK_URL=https://your-n8n-domain.example.com` | same value in env file |
| `SUPABASE_URL` | same value in env file |
| `SUPABASE_SERVICE_KEY` | rotate first, then add to env file |
| `C:\Users\Admin\node_modules` | `/opt/n8n/custom` |
| `C:\Users\Admin\Documents,...` | `/opt/obsidian-vault,/opt/n8n-backup,/tmp` |

## Hook Loading

n8n loads backend hooks from:

```bash
EXTERNAL_HOOK_FILES=/opt/n8n/execution-hooks.js
```

The hook writes only execution metadata to Supabase. It does not write raw input,
output, node data, or PII.

## Browser Automation

Local Playwright is installed for workflows that need `chromium.launch()`.
Browserless remains available for remote CDP workflows:

```bash
BROWSERLESS_WS_URL=ws://browserless.example.internal:3000?token=replace_with_token&timeout=55000
```

## Execute Command Node

`N8N_ENABLE_EXECUTE_COMMAND=true` is kept for parity with Windows. This is risky.
Keep this instance private, admin-only, and behind trusted network controls.

## Obsidian MCP

The Windows script starts an MCP filesystem proxy. This repo does not install MCP
by default. Keep MCP as a separate service if needed so n8n uptime is not tied to
Obsidian tooling.

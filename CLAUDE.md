# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is the **deployment configuration repository** for the Falcon Trading Platform. It contains SystemD service files, nginx configuration, and node setup scripts. The main application source code lives at `/home/ospartners/src/falcon/`.

## Node Setup

```bash
sudo ./setup-node.sh compute   # Stock screener + paper trader services
sudo ./setup-node.sh web       # Dashboard (Flask) + nginx reverse proxy
sudo ./setup-node.sh db        # PostgreSQL instructions only (manual setup)
```

After any node setup, configure secrets:
```bash
sudo cp /path/to/secrets.env /etc/falcon/secrets.env
sudo chmod 600 /etc/falcon/secrets.env
```

## Service Management

```bash
# View logs
sudo journalctl -u falcon-screener@morning -f
sudo journalctl -u falcon-dashboard -f

# Start/stop individual services
sudo systemctl start falcon-dashboard
sudo systemctl start falcon-trader
sudo systemctl start falcon-orchestrator

# Enable/disable scheduled screener timers
sudo systemctl enable falcon-screener@morning.timer
sudo systemctl enable falcon-screener@midday.timer
sudo systemctl enable falcon-screener@evening.timer

# Check all falcon service statuses
sudo systemctl list-units 'falcon-*'
```

## Architecture

### Node Roles

| Node Type | Services Installed | Purpose |
|-----------|-------------------|---------|
| `compute` | `falcon-screener@*`, `falcon-trader` | AI screening + paper trading execution |
| `web` | `falcon-dashboard`, nginx | REST API + web UI on port 80 |
| `db` | (manual) | PostgreSQL for multi-node deployments |

### Service Overview

**Screener Services** (compute node):
- `falcon-screener@.service` — Parameterized oneshot; runs with `--run-type %i` (morning/midday/evening)
- `falcon-screener@morning.timer` — Fires at 4:00 AM
- `falcon-screener@midday.timer` — Hourly 9 AM–12 PM
- `falcon-screener@evening.timer` — Fires at 7:00 PM

**Trading Services** (compute node):
- `falcon-trader.service` — Paper trading engine
- `falcon-orchestrator.service` / `falcon-orchestrator-daemon.service` — Multi-strategy orchestration
- `falcon-strategy.service` — Strategy execution
- `falcon-stop-loss.service` — Stop-loss monitor

**Web Services** (web node):
- `falcon-dashboard.service` — Flask server on `127.0.0.1:5000`
- `falcon-dashboard-fhs.service` — FHS-compliant variant

### Nginx

Config at `nginx/falcon.conf` proxies all traffic to Flask on port 5000. SSL is commented out by default. To enable HTTPS, uncomment the `listen 443 ssl http2` block and provide cert paths.

Install:
```bash
sudo cp nginx/falcon.conf /etc/nginx/sites-available/falcon
sudo ln -s /etc/nginx/sites-available/falcon /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

### FHS Directory Layout

All services run as `falcon:falcon` with access limited to:
- `/opt/falcon/venv/` — Python virtualenv (installed from GitHub packages)
- `/var/lib/falcon/` — Data (DB, market data, screened stocks)
- `/var/cache/falcon/` — Cache
- `/etc/falcon/secrets.env` — API keys and config (mode 600)

### Application Packages

The setup script installs packages directly from GitHub:
- `git+https://github.com/TradingAsBuddies/falcon-screener.git`
- `git+https://github.com/TradingAsBuddies/falcon-trader.git`

For local development installs, use the Makefile in `/home/ospartners/src/falcon/` instead.

## Required Secrets (`/etc/falcon/secrets.env`)

```bash
MASSIVE_API_KEY=        # Polygon.io API key (required for market data)
CLAUDE_API_KEY=         # Claude API key (primary AI screener)
OPENAI_API_KEY=         # ChatGPT API key (fallback screener)
PERPLEXITY_API_KEY=     # Perplexity API key (fallback screener)
DB_TYPE=sqlite          # or 'postgresql' for multi-node
DB_PASSWORD=            # PostgreSQL password (if DB_TYPE=postgresql)
FALCON_ENV=production
```

# Falcon Deploy

Deployment scripts and infrastructure for the Falcon Trading Platform.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        192.168.1.162                            │
│                      falcon-web (Web/Proxy)                     │
│                                                                 │
│  ┌─────────────┐    ┌─────────────────────────────────────┐    │
│  │   nginx     │───▶│      falcon-dashboard (Flask)       │    │
│  │  :80/:443   │    │           :5000                     │    │
│  └─────────────┘    └─────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                        192.168.1.194                            │
│                     falcon-db (Database)                        │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   PostgreSQL :5432                       │   │
│  │                   Database: falcon                       │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                                ▲
                                │
┌─────────────────────────────────────────────────────────────────┐
│                        192.168.1.232                            │
│                  falcon-compute (Compute/Storage)               │
│                                                                 │
│  ┌──────────────────┐    ┌──────────────────────────────────┐  │
│  │  falcon-screener │    │         falcon-trader            │  │
│  │  (scheduled)     │    │    (trading orchestrator)        │  │
│  │  morning/midday/ │    │                                  │  │
│  │  evening timers  │    │                                  │  │
│  └──────────────────┘    └──────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              /var/lib/falcon/market_data/                │  │
│  │                (NVMe storage for flat files)             │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Set Up Database (192.168.1.194)

```bash
ssh ospartners@192.168.1.194
./setup-postgres.sh <your_db_password>
```

### 2. Configure Secrets

Edit the config files with your API keys and database password:

```bash
# Edit config/falcon-compute.env
# Edit config/falcon-web.env
```

### 3. Deploy Nodes

```bash
# Deploy all nodes
./scripts/deploy.sh setup all

# Or deploy individually
./scripts/deploy.sh setup compute
./scripts/deploy.sh setup web
```

### 4. Deploy Secrets

```bash
./scripts/deploy.sh secrets all
```

### 5. Start Services

```bash
./scripts/deploy.sh start all
```

## Repository Structure

```
falcon-deploy/
├── inventory/
│   └── hosts.yaml          # Node inventory (Ansible-compatible)
├── config/
│   ├── falcon-compute.env  # Environment for compute node
│   └── falcon-web.env      # Environment for web node
├── services/
│   ├── falcon-screener@.service      # Screener template service
│   ├── falcon-screener@morning.timer # Morning screen timer
│   ├── falcon-screener@midday.timer  # Midday screen timer
│   ├── falcon-screener@evening.timer # Evening screen timer
│   ├── falcon-trader.service         # Trading bot service
│   └── falcon-dashboard.service      # Dashboard service
├── nginx/
│   └── falcon.conf         # Nginx reverse proxy config
├── scripts/
│   ├── deploy.sh           # Main deployment script
│   ├── setup-node.sh       # Individual node setup
│   └── setup-postgres.sh   # PostgreSQL setup
└── README.md
```

## Node Roles

| Node | IP | Role | Packages |
|------|-----|------|----------|
| falcon-db | 192.168.1.194 | Database | PostgreSQL |
| falcon-compute | 192.168.1.232 | Screener + Trader | falcon-screener, falcon-trader |
| falcon-web | 192.168.1.162 | Dashboard + Proxy | falcon-trader, nginx |

## Service Management

```bash
# Check status
./scripts/deploy.sh status all

# View logs
./scripts/deploy.sh logs compute
./scripts/deploy.sh logs web

# Start/Stop services
./scripts/deploy.sh start compute
./scripts/deploy.sh stop web

# Manual service control on nodes
ssh davdunc@192.168.1.232 "sudo systemctl status falcon-trader"
ssh ospartners@192.168.1.162 "sudo systemctl status falcon-dashboard"
```

## Screener Schedule

| Timer | Time (ET) | Description |
|-------|-----------|-------------|
| morning | 4:00 AM | Pre-market scan |
| midday | 10:00 AM | Mid-session scan |
| evening | 7:00 PM | After-hours review |

## FHS Paths

| Path | Purpose |
|------|---------|
| `/opt/falcon/venv/` | Python virtual environment |
| `/etc/falcon/secrets.env` | API keys and secrets |
| `/var/lib/falcon/` | Data directory |
| `/var/lib/falcon/market_data/` | Market data flat files |
| `/var/cache/falcon/` | Cache directory |
| `/var/log/falcon/` | Log directory |

## Updating Packages

```bash
# Update packages on compute node
ssh davdunc@192.168.1.232
sudo /opt/falcon/venv/bin/pip install --upgrade \
    git+https://github.com/TradingAsBuddies/falcon-screener.git \
    git+https://github.com/TradingAsBuddies/falcon-trader.git
sudo systemctl restart falcon-trader

# Update packages on web node
ssh ospartners@192.168.1.162
sudo /opt/falcon/venv/bin/pip install --upgrade \
    git+https://github.com/TradingAsBuddies/falcon-trader.git
sudo systemctl restart falcon-dashboard
```

## Troubleshooting

### Database Connection Issues

```bash
# Test connection from compute node
psql -h 192.168.1.194 -U falcon -d falcon -c "SELECT 1"

# Check PostgreSQL is listening
ssh ospartners@192.168.1.194 "sudo ss -tlnp | grep 5432"
```

### Service Issues

```bash
# Check service logs
journalctl -u falcon-screener@morning -f
journalctl -u falcon-trader -f
journalctl -u falcon-dashboard -f

# Check nginx
sudo nginx -t
sudo tail -f /var/log/nginx/falcon_error.log
```

## License

MIT

# Falcon Deploy

Deployment scripts and infrastructure for the Falcon Trading Platform.

## Repository Structure

```
falcon-deploy/
├── inventory/          # Ansible inventory
│   └── hosts.yaml      # Host definitions
├── services/           # Systemd service files
│   ├── falcon-dashboard.service
│   ├── falcon-screener.service
│   ├── falcon-trader.service
│   └── ...
├── scripts/            # Utility scripts
│   └── discover.sh     # Network discovery
├── backup-db.sh        # Database backup
├── install-services.sh # Install systemd services
├── status.sh           # Check service status
├── logs.sh             # View service logs
├── sync.sh             # Sync to remote hosts
└── restart-services.sh # Restart all services
```

## Deployment Topology

| Component | Package | Node |
|-----------|---------|------|
| Core Libraries | falcon-core | All nodes (pip) |
| Screener | falcon-screener | Screener node |
| Trader | falcon-trader | Trading node |
| Dashboard | falcon-trader | API node |

## Quick Start

### 1. Configure Inventory

Edit `inventory/hosts.yaml`:
```yaml
all:
  children:
    screener:
      hosts:
        pi-screener:
          ansible_host: 192.168.1.101
    trader:
      hosts:
        pi-trader:
          ansible_host: 192.168.1.102
```

### 2. Install on Remote Hosts

```bash
# SSH to each node and install packages
ssh pi-screener
pip install git+https://github.com/TradingAsBuddies/falcon-screener.git

ssh pi-trader
pip install git+https://github.com/TradingAsBuddies/falcon-trader.git
```

### 3. Install Services

```bash
# Copy service files and enable
./install-services.sh
```

### 4. Start Services

```bash
./restart-services.sh
```

## Service Management

```bash
# Check status
./status.sh

# View logs
./logs.sh falcon-screener
./logs.sh falcon-trader

# Restart
./restart-services.sh
```

## Backup

```bash
# Backup database
./backup-db.sh
```

## License

MIT

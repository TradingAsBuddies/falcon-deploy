#!/bin/bash
# Sync falcon application from control node to compute node
# Usage: ./deploy/sync.sh [--restart]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="$PROJECT_DIR/apps/falcon"
REMOTE_USER="ospartners"
REMOTE_HOST="192.168.1.162"
REMOTE_DIR="/home/ospartners/src/falcon"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Falcon Deployment ===${NC}"
echo ""

# Check if app directory exists
if [ ! -d "$APP_DIR" ]; then
    echo -e "${RED}Error: App directory not found: $APP_DIR${NC}"
    exit 1
fi

# Test SSH connection
echo -e "${YELLOW}Testing SSH connection...${NC}"
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes ${REMOTE_USER}@${REMOTE_HOST} "echo connected" &>/dev/null; then
    echo -e "${RED}Error: Cannot connect to ${REMOTE_HOST}${NC}"
    exit 1
fi
echo -e "${GREEN}SSH connection OK${NC}"
echo ""

# Show what will be synced
echo -e "${YELLOW}Files to sync:${NC}"
rsync -avzn --delete \
    --exclude '.git' \
    --exclude '__pycache__' \
    --exclude '*.pyc' \
    --exclude 'backtest/lib' \
    --exclude 'backtest/bin' \
    --exclude '*.db' \
    --exclude '.env' \
    --exclude 'paper_trading.pid' \
    --exclude 'paper_trading.log' \
    --exclude 'dashboard.log' \
    --exclude 'screened_stocks.json' \
    --exclude 'market_data/' \
    "$APP_DIR/" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/" 2>/dev/null | head -20

echo ""
read -p "Proceed with sync? (y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Sync files
echo ""
echo -e "${YELLOW}Syncing files...${NC}"
rsync -avz --delete \
    --exclude '.git' \
    --exclude '__pycache__' \
    --exclude '*.pyc' \
    --exclude 'backtest/lib' \
    --exclude 'backtest/bin' \
    --exclude '*.db' \
    --exclude '.env' \
    --exclude 'paper_trading.pid' \
    --exclude 'paper_trading.log' \
    --exclude 'dashboard.log' \
    --exclude 'screened_stocks.json' \
    --exclude 'market_data/' \
    "$APP_DIR/" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/"

echo ""
echo -e "${GREEN}Sync complete!${NC}"

# Restart services if requested
if [ "$1" == "--restart" ]; then
    echo ""
    echo -e "${YELLOW}Restarting services...${NC}"

    ssh ${REMOTE_USER}@${REMOTE_HOST} << 'EOF'
        echo "Restarting dashboard..."
        sudo systemctl restart falcon-dashboard 2>/dev/null || echo "falcon-dashboard not a systemd service"

        echo "Restarting orchestrator..."
        sudo systemctl restart falcon-orchestrator 2>/dev/null || echo "falcon-orchestrator not a systemd service"

        echo ""
        echo "Service status:"
        ps aux | grep -E 'dashboard_server|run_orchestrator|ai_stock_screener|stop_loss' | grep -v grep
EOF

    echo ""
    echo -e "${GREEN}Services restarted!${NC}"
fi

echo ""
echo -e "${GREEN}=== Deployment Complete ===${NC}"

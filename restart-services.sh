#!/bin/bash
# Restart all Falcon services in correct order
# Usage: ./deploy/restart-services.sh [--stop-only]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

STOP_ONLY=false
if [ "$1" == "--stop-only" ]; then
    STOP_ONLY=true
fi

echo -e "${GREEN}=== Falcon Service Restart ===${NC}"
echo ""

ssh ospartners@192.168.1.162 << EOF
    echo -e "${YELLOW}Stopping services...${NC}"

    # Stop in reverse dependency order
    sudo systemctl stop falcon-stop-loss 2>/dev/null || true
    sudo systemctl stop falcon-orchestrator 2>/dev/null || true
    sudo systemctl stop falcon-strategy 2>/dev/null || true
    sudo systemctl stop falcon-screener 2>/dev/null || true
    sudo systemctl stop falcon-dashboard 2>/dev/null || true

    echo "All services stopped"

    if [ "$STOP_ONLY" != "true" ]; then
        echo ""
        echo -e "${YELLOW}Starting services...${NC}"

        # Start in dependency order
        sudo systemctl start falcon-dashboard
        sleep 2
        sudo systemctl start falcon-screener
        sudo systemctl start falcon-strategy
        sudo systemctl start falcon-orchestrator
        sudo systemctl start falcon-stop-loss

        echo ""
        echo "Service status:"
        sudo systemctl status falcon-dashboard --no-pager | head -5
        sudo systemctl status falcon-screener --no-pager | head -5
        sudo systemctl status falcon-strategy --no-pager | head -5
        sudo systemctl status falcon-orchestrator --no-pager | head -5
        sudo systemctl status falcon-stop-loss --no-pager | head -5
    fi
EOF

echo ""
echo -e "${GREEN}=== Done ===${NC}"

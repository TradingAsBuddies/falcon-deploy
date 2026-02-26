#!/bin/bash
# Install/update systemd services on falcon-compute
# Usage: ./deploy/install-services.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICES_DIR="$SCRIPT_DIR/services"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Falcon Service Installation ===${NC}"
echo ""

# First run service user setup
echo -e "${YELLOW}Step 1: Setting up service users...${NC}"
"$SCRIPT_DIR/setup-service-users.sh"
echo ""

# Copy service files to remote
echo -e "${YELLOW}Step 2: Installing systemd service files...${NC}"

for service_file in "$SERVICES_DIR"/*.service; do
    service_name=$(basename "$service_file")
    echo "  Installing $service_name..."
    scp "$service_file" ospartners@192.168.1.162:/tmp/
    ssh ospartners@192.168.1.162 "sudo mv /tmp/$service_name /etc/systemd/system/ && sudo chmod 644 /etc/systemd/system/$service_name"
done

echo -e "${GREEN}Service files installed${NC}"
echo ""

# Reload systemd
echo -e "${YELLOW}Step 3: Reloading systemd...${NC}"
ssh ospartners@192.168.1.162 "sudo systemctl daemon-reload"
echo -e "${GREEN}Done${NC}"
echo ""

# Enable services
echo -e "${YELLOW}Step 4: Enabling services...${NC}"
ssh ospartners@192.168.1.162 << 'EOF'
    sudo systemctl enable falcon-dashboard
    sudo systemctl enable falcon-screener
    sudo systemctl enable falcon-orchestrator
    sudo systemctl enable falcon-stop-loss
    sudo systemctl enable falcon-strategy
EOF
echo -e "${GREEN}Done${NC}"
echo ""

echo -e "${YELLOW}Services installed but NOT restarted.${NC}"
echo ""
echo "To restart all services, run:"
echo "  ./deploy/restart-services.sh"
echo ""
echo "Or restart individually:"
echo "  ssh ospartners@192.168.1.162 'sudo systemctl restart falcon-dashboard'"
echo ""
echo -e "${GREEN}=== Installation Complete ===${NC}"

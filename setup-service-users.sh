#!/bin/bash
# Set up falcon service user on all nodes
# Run this once to standardize service accounts

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Falcon Service User Setup ===${NC}"
echo ""

# falcon-db (192.168.1.194)
echo -e "${YELLOW}Setting up falcon user on falcon-db (192.168.1.194)...${NC}"
ssh ospartners@192.168.1.194 << 'EOF'
    # Create falcon system user if it doesn't exist
    if ! id falcon &>/dev/null; then
        sudo useradd --system --no-create-home --shell /usr/sbin/nologin falcon
        echo "Created falcon system user"
    else
        echo "falcon user already exists"
    fi

    # Create data directory
    sudo mkdir -p /var/lib/falcon
    sudo chown falcon:falcon /var/lib/falcon
    sudo chmod 750 /var/lib/falcon

    echo "falcon-db setup complete"
EOF
echo -e "${GREEN}Done${NC}"
echo ""

# falcon-compute (192.168.1.162)
echo -e "${YELLOW}Setting up falcon user permissions on falcon-compute (192.168.1.162)...${NC}"
ssh ospartners@192.168.1.162 << 'EOF'
    # Ensure falcon user exists (it should)
    if ! id falcon &>/dev/null; then
        sudo useradd --system --home /opt/falcon --shell /usr/sbin/nologin falcon
        echo "Created falcon system user"
    else
        echo "falcon user already exists: $(id falcon)"
    fi

    # Create required directories
    sudo mkdir -p /var/lib/falcon
    sudo mkdir -p /var/log/falcon
    sudo chown falcon:falcon /var/lib/falcon /var/log/falcon
    sudo chmod 750 /var/lib/falcon /var/log/falcon

    # Copy env file for falcon user
    if [ -f /home/ospartners/.local/.env ]; then
        sudo cp /home/ospartners/.local/.env /opt/falcon/.env
        sudo chown falcon:falcon /opt/falcon/.env
        sudo chmod 600 /opt/falcon/.env
        echo "Copied .env to /opt/falcon/.env"
    fi

    # Create symlink to src for easier management
    if [ ! -L /opt/falcon/src ]; then
        sudo ln -sf /home/ospartners/src/falcon /opt/falcon/src
        echo "Created symlink /opt/falcon/src -> /home/ospartners/src/falcon"
    fi

    # Give falcon read access to application code
    sudo usermod -aG ospartners falcon 2>/dev/null || true

    # Set permissions on app directory
    chmod -R g+rX /home/ospartners/src/falcon
    chmod g+w /home/ospartners/src/falcon/screened_stocks.json 2>/dev/null || true
    chmod g+w /home/ospartners/src/falcon/paper_trading.db 2>/dev/null || true
    chmod g+w /home/ospartners/src/falcon/dashboard.log 2>/dev/null || true

    echo "falcon-compute setup complete"
EOF
echo -e "${GREEN}Done${NC}"
echo ""

echo -e "${GREEN}=== Service User Setup Complete ===${NC}"

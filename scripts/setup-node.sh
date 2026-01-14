#!/bin/bash
# Falcon Node Setup Script
# Usage: ./setup-node.sh <node-type>
# Node types: compute, web, db

set -e

NODE_TYPE="${1:-}"
FALCON_USER="falcon"
FALCON_GROUP="falcon"
VENV_PATH="/opt/falcon/venv"
DATA_PATH="/var/lib/falcon"
CACHE_PATH="/var/cache/falcon"
LOG_PATH="/var/log/falcon"
CONFIG_PATH="/etc/falcon"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [[ -z "$NODE_TYPE" ]]; then
    echo "Usage: $0 <node-type>"
    echo "Node types: compute, web, db"
    exit 1
fi

log_info "Setting up Falcon $NODE_TYPE node..."

# Create falcon user if it doesn't exist
if ! id "$FALCON_USER" &>/dev/null; then
    log_info "Creating falcon user..."
    sudo useradd -r -s /bin/false -d "$DATA_PATH" "$FALCON_USER"
fi

# Create FHS-compliant directories
log_info "Creating directories..."
sudo mkdir -p "$DATA_PATH" "$CACHE_PATH" "$LOG_PATH" "$CONFIG_PATH"
sudo chown "$FALCON_USER:$FALCON_GROUP" "$DATA_PATH" "$CACHE_PATH" "$LOG_PATH"
sudo chmod 750 "$DATA_PATH" "$CACHE_PATH" "$LOG_PATH"
sudo chmod 755 "$CONFIG_PATH"

# Create Python virtual environment
log_info "Creating Python virtual environment..."
sudo mkdir -p /opt/falcon
sudo python3 -m venv "$VENV_PATH"
sudo chown -R "$FALCON_USER:$FALCON_GROUP" /opt/falcon

# Install packages based on node type
case "$NODE_TYPE" in
    compute)
        log_info "Installing falcon-screener and falcon-trader..."
        sudo "$VENV_PATH/bin/pip" install --upgrade pip
        sudo "$VENV_PATH/bin/pip" install \
            git+https://github.com/TradingAsBuddies/falcon-screener.git \
            git+https://github.com/TradingAsBuddies/falcon-trader.git

        # Create market data directory
        sudo mkdir -p "$DATA_PATH/market_data"
        sudo chown "$FALCON_USER:$FALCON_GROUP" "$DATA_PATH/market_data"

        # Install systemd services
        log_info "Installing systemd services..."
        sudo cp services/falcon-screener@.service /etc/systemd/system/
        sudo cp services/falcon-screener@morning.timer /etc/systemd/system/
        sudo cp services/falcon-screener@midday.timer /etc/systemd/system/
        sudo cp services/falcon-screener@evening.timer /etc/systemd/system/
        sudo cp services/falcon-trader.service /etc/systemd/system/

        sudo systemctl daemon-reload
        sudo systemctl enable falcon-screener@morning.timer
        sudo systemctl enable falcon-screener@midday.timer
        sudo systemctl enable falcon-screener@evening.timer
        sudo systemctl enable falcon-trader
        ;;

    web)
        log_info "Installing falcon-trader (dashboard)..."
        sudo "$VENV_PATH/bin/pip" install --upgrade pip
        sudo "$VENV_PATH/bin/pip" install \
            git+https://github.com/TradingAsBuddies/falcon-trader.git

        # Install systemd service
        log_info "Installing systemd services..."
        sudo cp services/falcon-dashboard.service /etc/systemd/system/

        # Install nginx config
        log_info "Configuring nginx..."
        sudo cp nginx/falcon.conf /etc/nginx/sites-available/falcon
        sudo ln -sf /etc/nginx/sites-available/falcon /etc/nginx/sites-enabled/
        sudo rm -f /etc/nginx/sites-enabled/default
        sudo nginx -t

        sudo systemctl daemon-reload
        sudo systemctl enable falcon-dashboard
        sudo systemctl reload nginx
        ;;

    db)
        log_info "Database node - PostgreSQL setup"
        log_info "Ensure PostgreSQL is installed and configured with:"
        echo "  CREATE USER falcon WITH PASSWORD 'your_password';"
        echo "  CREATE DATABASE falcon OWNER falcon;"
        echo "  GRANT ALL PRIVILEGES ON DATABASE falcon TO falcon;"
        ;;

    *)
        log_error "Unknown node type: $NODE_TYPE"
        exit 1
        ;;
esac

log_info "Node setup complete!"
log_warn "Don't forget to:"
echo "  1. Copy secrets.env to $CONFIG_PATH/secrets.env"
echo "  2. Set proper permissions: sudo chmod 600 $CONFIG_PATH/secrets.env"
echo "  3. Start services: sudo systemctl start <service-name>"

#!/bin/bash
# PostgreSQL Setup for Falcon Trading Platform
# Run this on the database server (192.168.1.194)

set -e

DB_NAME="falcon"
DB_USER="falcon"
DB_PASSWORD="${1:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [[ -z "$DB_PASSWORD" ]]; then
    echo "Usage: $0 <db_password>"
    echo "Creates the falcon database and user for the trading platform."
    exit 1
fi

log_info "Setting up PostgreSQL for Falcon Trading Platform..."

# Check if PostgreSQL is installed
if ! command -v psql &> /dev/null; then
    log_info "Installing PostgreSQL..."
    sudo apt-get update
    sudo apt-get install -y postgresql postgresql-contrib
fi

# Create user and database
log_info "Creating database user and database..."
sudo -u postgres psql <<EOF
-- Create user if not exists
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$DB_USER') THEN
        CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';
    ELSE
        ALTER USER $DB_USER WITH PASSWORD '$DB_PASSWORD';
    END IF;
END
\$\$;

-- Create database if not exists
SELECT 'CREATE DATABASE $DB_NAME OWNER $DB_USER'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DB_NAME')\gexec

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
EOF

# Configure PostgreSQL to accept remote connections
PG_CONF=$(sudo -u postgres psql -t -c "SHOW config_file" | tr -d ' ')
PG_HBA=$(dirname "$PG_CONF")/pg_hba.conf

log_info "Configuring remote access..."

# Update postgresql.conf to listen on all interfaces
sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_CONF"

# Add entries to pg_hba.conf for local network
if ! grep -q "192.168.1.0/24" "$PG_HBA"; then
    echo "# Falcon Trading Platform - Allow local network" | sudo tee -a "$PG_HBA"
    echo "host    $DB_NAME    $DB_USER    192.168.1.0/24    scram-sha-256" | sudo tee -a "$PG_HBA"
fi

# Restart PostgreSQL
log_info "Restarting PostgreSQL..."
sudo systemctl restart postgresql

# Verify
log_info "Verifying setup..."
sudo -u postgres psql -c "SELECT datname FROM pg_database WHERE datname = '$DB_NAME';"

log_info "PostgreSQL setup complete!"
echo ""
echo "Connection details:"
echo "  Host: $(hostname -I | awk '{print $1}')"
echo "  Port: 5432"
echo "  Database: $DB_NAME"
echo "  User: $DB_USER"
echo ""
log_warn "Add this password to your secrets.env files:"
echo "  DB_PASSWORD=$DB_PASSWORD"

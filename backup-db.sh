#!/bin/bash
# Backup PostgreSQL databases from falcon-db to control node
# Usage: ./deploy/backup-db.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_DIR/backups"
REMOTE_USER="ospartners"
REMOTE_HOST="192.168.1.194"
DATE=$(date +%Y%m%d_%H%M%S)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Database Backup ===${NC}"
echo ""

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Test SSH connection
echo -e "${YELLOW}Testing SSH connection to falcon-db...${NC}"
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes ${REMOTE_USER}@${REMOTE_HOST} "echo connected" &>/dev/null; then
    echo -e "${RED}Error: Cannot connect to ${REMOTE_HOST}${NC}"
    exit 1
fi
echo -e "${GREEN}SSH connection OK${NC}"
echo ""

# Backup trading database
echo -e "${YELLOW}Backing up 'trading' database...${NC}"
ssh ${REMOTE_USER}@${REMOTE_HOST} "sudo -u postgres pg_dump trading" | gzip > "$BACKUP_DIR/trading_${DATE}.sql.gz"
echo -e "${GREEN}Saved: trading_${DATE}.sql.gz${NC}"

# Backup finviz database
echo -e "${YELLOW}Backing up 'finviz' database...${NC}"
ssh ${REMOTE_USER}@${REMOTE_HOST} "sudo -u postgres pg_dump finviz" | gzip > "$BACKUP_DIR/finviz_${DATE}.sql.gz"
echo -e "${GREEN}Saved: finviz_${DATE}.sql.gz${NC}"

echo ""
echo -e "${GREEN}=== Backup Complete ===${NC}"
echo ""
echo "Backups saved to: $BACKUP_DIR"
ls -lh "$BACKUP_DIR"/*.gz 2>/dev/null | tail -5

# Clean up old backups (keep last 7)
echo ""
echo -e "${YELLOW}Cleaning up old backups (keeping last 7)...${NC}"
cd "$BACKUP_DIR"
ls -t trading_*.sql.gz 2>/dev/null | tail -n +8 | xargs -r rm -f
ls -t finviz_*.sql.gz 2>/dev/null | tail -n +8 | xargs -r rm -f
echo -e "${GREEN}Done${NC}"

#!/bin/bash
# Discover applications and services running on remote Pis

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
INVENTORY_DIR="$PROJECT_DIR/inventory"

echo "=== Falcon Operator Discovery ==="
echo ""

# Database node
echo ">>> Discovering falcon-db (192.168.1.194)..."
if ssh -o ConnectTimeout=5 -o BatchMode=yes 192.168.1.194 "echo connected" &>/dev/null; then
    echo "  [OK] SSH connection successful"

    echo "  Checking PostgreSQL..."
    ssh 192.168.1.194 "sudo systemctl status postgresql --no-pager 2>/dev/null || echo 'PostgreSQL not running as systemd service'" | head -5

    echo "  Checking disk usage..."
    ssh 192.168.1.194 "df -h / | tail -1"

    echo "  Finding application directories..."
    ssh 192.168.1.194 "ls -la ~/Projects 2>/dev/null || ls -la ~/ | grep -E '^d'" | head -10

    echo "  Checking running Python processes..."
    ssh 192.168.1.194 "ps aux | grep -E 'python|node' | grep -v grep" | head -5
else
    echo "  [FAIL] Cannot connect via SSH - run: ssh-copy-id 192.168.1.194"
fi

echo ""

# Compute node
echo ">>> Discovering falcon-compute (192.168.1.162)..."
if ssh -o ConnectTimeout=5 -o BatchMode=yes 192.168.1.162 "echo connected" &>/dev/null; then
    echo "  [OK] SSH connection successful"

    echo "  Checking nginx..."
    ssh 192.168.1.162 "sudo systemctl status nginx --no-pager 2>/dev/null || echo 'nginx not running'" | head -5

    echo "  Checking disk usage..."
    ssh 192.168.1.162 "df -h / | tail -1"

    echo "  Finding application directories..."
    ssh 192.168.1.162 "ls -la ~/Projects 2>/dev/null || ls -la ~/ | grep -E '^d'" | head -10

    echo "  Checking running Python processes..."
    ssh 192.168.1.162 "ps aux | grep -E 'python|node' | grep -v grep" | head -5

    echo "  Checking nginx sites..."
    ssh 192.168.1.162 "ls /etc/nginx/sites-enabled/ 2>/dev/null" || echo "  Could not list nginx sites"
else
    echo "  [FAIL] Cannot connect via SSH - run: ssh-copy-id 192.168.1.162"
fi

echo ""
echo "=== Discovery Complete ==="

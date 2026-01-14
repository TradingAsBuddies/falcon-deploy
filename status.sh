#!/bin/bash
# Check status of all Falcon nodes
# Usage: ./deploy/status.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║              FALCON TRADING PLATFORM STATUS                ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# falcon-control (local)
echo -e "${GREEN}▶ falcon-control (localhost)${NC}"
echo "  Hostname: $(hostname)"
echo "  Disk: $(df -h / | tail -1 | awk '{print $4 " free of " $2}')"
echo ""

# falcon-db
echo -e "${GREEN}▶ falcon-db (192.168.1.194)${NC}"
if ssh -o ConnectTimeout=3 -o BatchMode=yes ospartners@192.168.1.194 "echo ok" &>/dev/null; then
    echo -e "  Status: ${GREEN}ONLINE${NC}"
    ssh ospartners@192.168.1.194 "
        echo \"  Hostname: \$(hostname)\"
        echo \"  Disk: \$(df -h / | tail -1 | awk '{print \$4 \" free of \" \$2}')\"

        if systemctl is-active postgresql &>/dev/null; then
            echo -e '  PostgreSQL: \033[0;32mRUNNING\033[0m'
        else
            echo -e '  PostgreSQL: \033[0;31mSTOPPED\033[0m'
        fi
    " 2>/dev/null
else
    echo -e "  Status: ${RED}OFFLINE${NC}"
fi
echo ""

# falcon-compute
echo -e "${GREEN}▶ falcon-compute (192.168.1.162)${NC}"
if ssh -o ConnectTimeout=3 -o BatchMode=yes ospartners@192.168.1.162 "echo ok" &>/dev/null; then
    echo -e "  Status: ${GREEN}ONLINE${NC}"
    ssh ospartners@192.168.1.162 "
        echo \"  Hostname: \$(hostname)\"
        echo \"  Disk: \$(df -h / | tail -1 | awk '{print \$4 \" free of \" \$2}')\"

        if systemctl is-active nginx &>/dev/null; then
            echo -e '  nginx: \033[0;32mRUNNING\033[0m'
        else
            echo -e '  nginx: \033[0;31mSTOPPED\033[0m'
        fi

        echo ''
        echo '  Python processes:'
        ps aux | grep -E 'dashboard_server|run_orchestrator|ai_stock_screener|stop_loss|strategy_orchestrator' | grep -v grep | while read line; do
            pid=\$(echo \$line | awk '{print \$2}')
            cmd=\$(echo \$line | awk '{for(i=11;i<=NF;i++) printf \$i\" \"; print \"\"}' | sed 's/.*\///' | cut -c1-50)
            cpu=\$(echo \$line | awk '{print \$3}')
            mem=\$(echo \$line | awk '{print \$4}')
            echo \"    PID \$pid: \$cmd (CPU: \$cpu%, MEM: \$mem%)\"
        done
    " 2>/dev/null
else
    echo -e "  Status: ${RED}OFFLINE${NC}"
fi

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"

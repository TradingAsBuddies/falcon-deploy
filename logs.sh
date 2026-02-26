#!/bin/bash
# View Falcon service logs
# Usage: ./deploy/logs.sh [service] [--follow]
#   service: dashboard, screener, orchestrator, stop-loss, strategy, all (default: all)
#   --follow: tail logs in real-time

SERVICE="${1:-all}"
FOLLOW=""

if [ "$2" == "--follow" ] || [ "$2" == "-f" ]; then
    FOLLOW="-f"
fi

case "$SERVICE" in
    dashboard)
        ssh ospartners@192.168.1.162 "sudo journalctl -u falcon-dashboard $FOLLOW -n 100"
        ;;
    screener)
        ssh ospartners@192.168.1.162 "sudo journalctl -u falcon-screener $FOLLOW -n 100"
        ;;
    orchestrator)
        ssh ospartners@192.168.1.162 "sudo journalctl -u falcon-orchestrator $FOLLOW -n 100"
        ;;
    stop-loss)
        ssh ospartners@192.168.1.162 "sudo journalctl -u falcon-stop-loss $FOLLOW -n 100"
        ;;
    strategy)
        ssh ospartners@192.168.1.162 "sudo journalctl -u falcon-strategy $FOLLOW -n 100"
        ;;
    all)
        ssh ospartners@192.168.1.162 "sudo journalctl -u 'falcon-*' $FOLLOW -n 200"
        ;;
    *)
        echo "Usage: ./deploy/logs.sh [dashboard|screener|orchestrator|stop-loss|strategy|all] [--follow]"
        exit 1
        ;;
esac

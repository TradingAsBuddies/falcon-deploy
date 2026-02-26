#!/bin/bash
# Falcon Feedback Loop Deployment Script
# Run this on falcon-compute (192.168.1.232) as a user with sudo access
set -euo pipefail

echo "=== Falcon Feedback Loop Deployment ==="

# Create scripts directory
echo "[1/5] Creating directories..."
sudo mkdir -p /opt/falcon/scripts

# Create sync script
echo "[2/5] Installing sync-backtests.sh..."
sudo tee /opt/falcon/scripts/sync-backtests.sh > /dev/null << 'SCRIPT'
#!/bin/bash
set -euo pipefail

SQLITE_DB="${HOME}/.local/share/falcon/backtest_results.db"
PG_HOST="${FALCON_DB_HOST:-192.168.1.194}"
PG_DB="${FALCON_DB_NAME:-falcon}"
PG_USER="${FALCON_DB_USER:-falcon}"

if [[ ! -f "$SQLITE_DB" ]]; then
    echo "SQLite database not found: $SQLITE_DB"
    exit 1
fi

echo "Syncing backtest results from SQLite to PostgreSQL..."

# Sync backtest_runs
COUNT=0
sqlite3 -separator $'\t' "$SQLITE_DB" "SELECT run_id, strategy_name, symbol, start_date, end_date, total_return, sharpe_ratio, max_drawdown, win_rate, total_trades, parameters, created_at FROM backtest_runs;" | \
while IFS=$'\t' read -r run_id strategy_name symbol start_date end_date total_return sharpe_ratio max_drawdown win_rate total_trades parameters created_at; do
    PGPASSWORD="$FALCON_DB_PASSWORD" psql -h "$PG_HOST" -U "$PG_USER" -d "$PG_DB" -q -c \
        "INSERT INTO backtest_runs (run_id, strategy_name, symbol, start_date, end_date, total_return, sharpe_ratio, max_drawdown, win_rate, total_trades, parameters, created_at)
         VALUES ('$run_id', '$strategy_name', '$symbol', '$start_date', '$end_date', $total_return, $sharpe_ratio, $max_drawdown, $win_rate, $total_trades, '$parameters', '$created_at')
         ON CONFLICT (run_id) DO NOTHING;" 2>/dev/null || true
    ((COUNT++)) || true
done
echo "  Processed backtest_runs"

# Sync feedback_results
sqlite3 -separator $'\t' "$SQLITE_DB" "SELECT feedback_id, run_date, strategy_name, recommendation, confidence_score, notes, created_at FROM feedback_results;" 2>/dev/null | \
while IFS=$'\t' read -r feedback_id run_date strategy_name recommendation confidence_score notes created_at; do
    PGPASSWORD="$FALCON_DB_PASSWORD" psql -h "$PG_HOST" -U "$PG_USER" -d "$PG_DB" -q -c \
        "INSERT INTO feedback_results (feedback_id, run_date, strategy_name, recommendation, confidence_score, notes, created_at)
         VALUES ('$feedback_id', '$run_date', '$strategy_name', '$recommendation', $confidence_score, '$notes', '$created_at')
         ON CONFLICT (feedback_id) DO NOTHING;" 2>/dev/null || true
done
echo "  Processed feedback_results"

# Update strategy_metrics aggregates
PGPASSWORD="$FALCON_DB_PASSWORD" psql -h "$PG_HOST" -U "$PG_USER" -d "$PG_DB" -q << 'SQL'
INSERT INTO strategy_metrics (strategy, stock_type, total_trades, winning_trades, losing_trades, total_return, avg_profit, win_rate, max_drawdown, sharpe_ratio, period_start, period_end)
SELECT
    strategy_name as strategy,
    'backtest' as stock_type,
    SUM(total_trades)::int as total_trades,
    ROUND(SUM(total_trades * win_rate / 100))::int as winning_trades,
    ROUND(SUM(total_trades * (1 - win_rate / 100)))::int as losing_trades,
    ROUND(SUM(total_return)::numeric, 2) as total_return,
    ROUND(AVG(total_return)::numeric, 2) as avg_profit,
    ROUND(AVG(win_rate)::numeric, 1) as win_rate,
    ROUND(MAX(max_drawdown)::numeric, 2) as max_drawdown,
    ROUND(AVG(sharpe_ratio)::numeric, 2) as sharpe_ratio,
    MIN(start_date) as period_start,
    MAX(end_date) as period_end
FROM backtest_runs
GROUP BY strategy_name
ON CONFLICT (strategy, stock_type, period_start, period_end)
DO UPDATE SET
    total_trades = EXCLUDED.total_trades,
    winning_trades = EXCLUDED.winning_trades,
    losing_trades = EXCLUDED.losing_trades,
    total_return = EXCLUDED.total_return,
    avg_profit = EXCLUDED.avg_profit,
    win_rate = EXCLUDED.win_rate,
    max_drawdown = EXCLUDED.max_drawdown,
    sharpe_ratio = EXCLUDED.sharpe_ratio,
    updated_at = NOW();
SQL
echo "  Updated strategy_metrics"

echo "Sync complete!"
SCRIPT

sudo chmod +x /opt/falcon/scripts/sync-backtests.sh

# Create systemd service files
echo "[3/5] Installing systemd services..."

sudo tee /etc/systemd/system/falcon-feedback.service > /dev/null << 'EOF'
[Unit]
Description=Falcon Feedback Loop - Daily Backtest Analysis
Documentation=https://github.com/TradingAsBuddies/falcon-deploy
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=falcon
Group=falcon
WorkingDirectory=/var/lib/falcon
EnvironmentFile=/etc/falcon/secrets.env
ExecStart=/opt/falcon/venv/bin/python -m falcon_core.backtesting.scheduler --run-now
StandardOutput=journal
StandardError=journal
SyslogIdentifier=falcon-feedback

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/falcon-feedback.timer > /dev/null << 'EOF'
[Unit]
Description=Falcon Feedback Loop Timer (11:30 AM ET weekdays)
Documentation=https://github.com/TradingAsBuddies/falcon-deploy

[Timer]
OnCalendar=Mon..Fri *-*-* 11:30:00 America/New_York
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo tee /etc/systemd/system/falcon-backtest-sync.service > /dev/null << 'EOF'
[Unit]
Description=Falcon Backtest Results Sync to PostgreSQL
Documentation=https://github.com/TradingAsBuddies/falcon-deploy
After=falcon-feedback.service
Wants=network-online.target

[Service]
Type=oneshot
User=falcon
Group=falcon
WorkingDirectory=/var/lib/falcon
EnvironmentFile=/etc/falcon/secrets.env
ExecStart=/opt/falcon/scripts/sync-backtests.sh
StandardOutput=journal
StandardError=journal
SyslogIdentifier=falcon-backtest-sync

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/falcon-backtest-sync.timer > /dev/null << 'EOF'
[Unit]
Description=Falcon Backtest Sync Timer (12:00 PM ET weekdays)
Documentation=https://github.com/TradingAsBuddies/falcon-deploy

[Timer]
OnCalendar=Mon..Fri *-*-* 12:00:00 America/New_York
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Reload and enable
echo "[4/5] Enabling timers..."
sudo systemctl daemon-reload
sudo systemctl enable falcon-feedback.timer falcon-backtest-sync.timer
sudo systemctl start falcon-feedback.timer falcon-backtest-sync.timer

# Verify
echo "[5/5] Verifying installation..."
echo ""
echo "=== Timer Status ==="
systemctl list-timers 'falcon-feedback*' 'falcon-backtest-sync*' --no-pager

echo ""
echo "=== Installation Complete ==="
echo ""
echo "To run feedback loop manually:"
echo "  sudo systemctl start falcon-feedback"
echo ""
echo "To sync backtests manually:"
echo "  sudo systemctl start falcon-backtest-sync"
echo ""
echo "To view logs:"
echo "  journalctl -u falcon-feedback -f"
echo "  journalctl -u falcon-backtest-sync -f"

#!/bin/bash
# Falcon Backtest Results Sync Script
# Syncs SQLite backtest results to PostgreSQL for dashboard access
#
# Requires: sqlite3, psql, DB_* environment variables

set -e

SQLITE_DB="${HOME}/.local/share/falcon/backtest_results.db"
LOG_PREFIX="[BACKTEST-SYNC]"

log_info() { echo "$LOG_PREFIX [INFO] $1"; }
log_error() { echo "$LOG_PREFIX [ERROR] $1" >&2; }

# Check prerequisites
if [[ ! -f "$SQLITE_DB" ]]; then
    log_error "SQLite database not found: $SQLITE_DB"
    exit 1
fi

if [[ -z "$DB_HOST" || -z "$DB_USER" || -z "$DB_PASSWORD" || -z "$DB_NAME" ]]; then
    log_error "Database environment variables not set (DB_HOST, DB_USER, DB_PASSWORD, DB_NAME)"
    exit 1
fi

export PGPASSWORD="$DB_PASSWORD"

log_info "Starting backtest sync from SQLite to PostgreSQL"
log_info "Source: $SQLITE_DB"
log_info "Target: postgresql://$DB_USER@$DB_HOST:${DB_PORT:-5432}/$DB_NAME"

# Create temp SQL file
TEMP_SQL=$(mktemp)
trap "rm -f $TEMP_SQL" EXIT

# Generate sync SQL from SQLite
log_info "Extracting data from SQLite..."

python3 << EOF > "$TEMP_SQL"
import sqlite3
import os

sqlite_path = os.environ.get('SQLITE_DB', os.path.expanduser('~/.local/share/falcon/backtest_results.db'))
conn = sqlite3.connect(sqlite_path)
conn.row_factory = sqlite3.Row
cursor = conn.cursor()

print("-- Falcon Backtest Sync")
print("-- Generated: $(date -Iseconds)")
print("")

# Sync backtest_runs (upsert based on strategy_name, symbol, trading_date)
print("-- Clear and reload backtest_runs")
print("TRUNCATE backtest_runs RESTART IDENTITY;")

cursor.execute('SELECT * FROM backtest_runs ORDER BY trading_date DESC')
for row in cursor.fetchall():
    params = str(row['parameters']).replace("'", "''") if row['parameters'] else None
    params_val = f"'{params}'" if params else 'NULL'

    print(f"""INSERT INTO backtest_runs (strategy_name, symbol, trading_date, interval, total_return, max_drawdown, sharpe_ratio, win_rate, total_trades, signals_count, parameters, created_at) VALUES ('{row['strategy_name']}', '{row['symbol']}', '{row['trading_date']}', '{row['interval']}', {row['total_return']}, {row['max_drawdown']}, {row['sharpe_ratio']}, {row['win_rate']}, {row['total_trades']}, {row['signals_count']}, {params_val}, '{row['created_at']}');""")

print("")

# Sync feedback_results
print("-- Clear and reload feedback_results")
print("TRUNCATE feedback_results RESTART IDENTITY;")

cursor.execute('SELECT * FROM feedback_results ORDER BY run_date DESC')
for row in cursor.fetchall():
    details = str(row['adjustment_details']).replace("'", "''") if row['adjustment_details'] else None
    details_val = f"'{details}'" if details else 'NULL'

    print(f"""INSERT INTO feedback_results (run_date, strategy_name, symbols_tested, total_trades, avg_return, avg_win_rate, avg_sharpe, adjustments_recommended, adjustments_applied, adjustment_details, created_at) VALUES ('{row['run_date']}', '{row['strategy_name']}', {row['symbols_tested']}, {row['total_trades']}, {row['avg_return']}, {row['avg_win_rate']}, {row['avg_sharpe']}, {bool(row['adjustments_recommended'])}, {bool(row['adjustments_applied'])}, {details_val}, '{row['created_at']}');""")

# Update strategy_metrics from backtest data
print("")
print("-- Update strategy_metrics from backtest aggregates")
print("""
INSERT INTO strategy_metrics (strategy, stock_type, period_start, period_end, total_trades, winning_trades, losing_trades, win_rate, avg_profit, total_return, max_drawdown, sharpe_ratio, updated_at)
SELECT
    strategy_name,
    'backtest' as stock_type,
    MIN(trading_date)::text,
    MAX(trading_date)::text,
    SUM(total_trades),
    ROUND(SUM(total_trades * win_rate / 100))::int,
    ROUND(SUM(total_trades * (1 - win_rate / 100)))::int,
    ROUND(AVG(win_rate)::numeric, 2),
    ROUND(AVG(total_return)::numeric * 100, 2),
    ROUND(SUM(total_return)::numeric * 100, 2),
    ROUND(MAX(max_drawdown)::numeric * 100, 2),
    ROUND(AVG(sharpe_ratio)::numeric, 2),
    NOW()::text
FROM backtest_runs
WHERE total_trades > 0
GROUP BY strategy_name
ON CONFLICT (strategy, stock_type, period_start, period_end) DO UPDATE SET
    total_trades = EXCLUDED.total_trades,
    winning_trades = EXCLUDED.winning_trades,
    losing_trades = EXCLUDED.losing_trades,
    win_rate = EXCLUDED.win_rate,
    avg_profit = EXCLUDED.avg_profit,
    total_return = EXCLUDED.total_return,
    max_drawdown = EXCLUDED.max_drawdown,
    sharpe_ratio = EXCLUDED.sharpe_ratio,
    updated_at = EXCLUDED.updated_at;
""")

conn.close()
EOF

# Execute sync
log_info "Syncing to PostgreSQL..."
SQLITE_DB="$SQLITE_DB" psql -h "$DB_HOST" -p "${DB_PORT:-5432}" -U "$DB_USER" -d "$DB_NAME" -f "$TEMP_SQL" > /dev/null

# Verify
COUNTS=$(psql -h "$DB_HOST" -p "${DB_PORT:-5432}" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM backtest_runs;")
log_info "Synced $COUNTS backtest runs to PostgreSQL"

# Sync SQLite to falcon-web for dashboard /api/backtests/* endpoints
FALCON_WEB_HOST="${FALCON_WEB_HOST:-falcon-api}"
FALCON_WEB_DB_PATH="/var/lib/falcon/.local/share/falcon/backtest_results.db"

if ssh -o BatchMode=yes -o ConnectTimeout=5 "$FALCON_WEB_HOST" true 2>/dev/null; then
    log_info "Syncing SQLite to falcon-web ($FALCON_WEB_HOST)..."
    scp -q "$SQLITE_DB" "$FALCON_WEB_HOST:/tmp/backtest_results.db" && \
    ssh "$FALCON_WEB_HOST" "sudo mv /tmp/backtest_results.db $FALCON_WEB_DB_PATH && sudo chown falcon:falcon $FALCON_WEB_DB_PATH"
    log_info "SQLite synced to falcon-web"
else
    log_info "Skipping falcon-web sync (host unreachable or no SSH key)"
fi

log_info "Sync complete"

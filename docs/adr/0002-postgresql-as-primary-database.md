# ADR 0002: PostgreSQL as Primary Database

## Status
Accepted

## Date
2026-01-14

## Context

The Falcon Trading Platform originally used SQLite for simplicity during development. As the platform evolved to support:
- Multiple concurrent services (screener, trader, dashboard)
- Distributed deployment across multiple nodes
- Complex queries for strategy backtesting
- YouTube strategy storage with full-text fields

SQLite's limitations became problematic:
1. Single-writer lock prevents concurrent writes
2. No network access - each node would need its own database
3. Limited data types (no native JSON, arrays)
4. No user authentication or access control

## Decision

Adopt PostgreSQL as the primary database with SQLite fallback for development.

### Configuration
```yaml
# Production (PostgreSQL)
DB_TYPE: postgresql
DB_HOST: 192.168.1.194
DB_PORT: 5432
DB_NAME: falcon
DB_USER: falcon

# Development (SQLite)
DB_TYPE: sqlite
DB_PATH: ./paper_trading.db
```

### Database Abstraction
The `falcon_core.DatabaseManager` class abstracts database operations:
- Automatic SQL placeholder conversion (`%s` for both backends)
- Connection pooling for PostgreSQL
- Schema initialization on startup
- Transparent JSON serialization

## Consequences

### Positive
- **Concurrent access**: Multiple services can read/write simultaneously
- **Network access**: All nodes connect to central database
- **Data integrity**: ACID transactions, foreign keys
- **Scalability**: Connection pooling, query optimization
- **Rich types**: Native JSON, arrays, timestamps

### Negative
- **Additional service**: PostgreSQL must be installed and maintained
- **Network latency**: Remote database adds ~1-5ms per query
- **Dependency**: `psycopg2-binary` package required
- **Migration complexity**: Schema changes need coordination

### Mitigations
- DatabaseManager handles both backends transparently
- Connection pooling minimizes connection overhead
- Schema versioning in DatabaseManager.init_schema()
- SQLite remains available for local development

## Implementation Details

### Schema Tables
```sql
-- Core trading tables
account, positions, orders, performance

-- Screener tables
screener_profiles, profile_runs, profile_performance

-- Strategy tables
youtube_strategies, strategy_backtests
```

### Network Configuration
PostgreSQL configured to accept connections from local network:
```
# pg_hba.conf
host    falcon    falcon    192.168.1.0/24    scram-sha-256
```

### Connection Handling
```python
from falcon_core import get_db_manager

db = get_db_manager()  # Auto-detects from environment
result = db.execute("SELECT * FROM positions", fetch='all')
```

## Alternatives Considered

### 1. MySQL/MariaDB
- Pros: Widely used, good tooling
- Cons: Less feature-rich than PostgreSQL, licensing concerns

### 2. MongoDB
- Pros: Schema flexibility, JSON-native
- Cons: No ACID by default, different query paradigm

### 3. Redis + SQLite
- Pros: Fast caching, simple persistence
- Cons: Adds complexity, still single-writer for SQLite

## References
- [PostgreSQL vs SQLite](https://www.postgresql.org/about/)
- [psycopg2 Documentation](https://www.psycopg.org/docs/)

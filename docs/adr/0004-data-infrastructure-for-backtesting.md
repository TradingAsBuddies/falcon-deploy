# ADR 0004: Data Infrastructure for Backtesting

## Status
Proposed

## Date
2026-01-15

## Context

After reviewing quantitative hedge fund data infrastructure practices (ref: YouTube strategy extraction), we identified gaps in Falcon's current data management that limit backtesting reliability:

1. **No data validation**: Bad data can corrupt backtest results silently
2. **Missing corporate actions**: Stock splits and dividends not tracked
3. **No data versioning**: Cannot reproduce historical backtests
4. **Limited fundamentals**: Only price/volume data, no earnings/financials
5. **No survivorship bias detection**: Delisted tickers not flagged
6. **Manual data refresh**: No automated pipeline for daily updates

## Decision

Implement a robust data infrastructure using open source components:

### Technology Stack

All tools selected are compatible with Apache License 2.0 (ASL-2.0) distribution.

| Component | Tool | License | Purpose |
|-----------|------|---------|---------|
| **Backtesting Engine** | VectorBT | Apache 2.0 | Vectorized backtesting with optimization |
| **Backtesting (optional)** | bt | MIT | Lightweight event-driven backtesting |
| **Data Storage** | PostgreSQL + TimescaleDB | PostgreSQL/Apache 2.0 | Time-series optimized relational storage |
| **Data Validation** | Pandera | MIT | Schema validation and data quality |
| **Data Versioning** | DVC (Data Version Control) | Apache 2.0 | Track data lineage and reproducibility |
| **Pipeline Orchestration** | Apache Airflow (or Prefect) | Apache 2.0 | Scheduled data refresh and ETL |
| **Market Data** | Polygon.io + yfinance | - | Primary and fallback data sources |

### Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        DATA INGESTION LAYER                         │
├─────────────────────────────────────────────────────────────────────┤
│  Polygon.io API  │  yfinance (fallback)  │  Finviz Fundamentals    │
└────────┬─────────┴───────────┬───────────┴────────────┬─────────────┘
         │                     │                        │
         ▼                     ▼                        ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        VALIDATION LAYER                             │
├─────────────────────────────────────────────────────────────────────┤
│  • Schema validation (Pandera)                                      │
│  • Price range checks (no negative prices, >1000% moves)            │
│  • Volume sanity checks                                             │
│  • Corporate action detection (splits, dividends)                   │
│  • Survivorship bias flagging (delisted tickers)                    │
│  • Gap detection (missing trading days)                             │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        STORAGE LAYER                                │
├─────────────────────────────────────────────────────────────────────┤
│  PostgreSQL + TimescaleDB                                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────────┐  │
│  │ daily_bars  │  │ minute_bars │  │ corporate_actions           │  │
│  │ (hypertable)│  │ (hypertable)│  │ (splits, dividends, delistings)│
│  └─────────────┘  └─────────────┘  └─────────────────────────────┘  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────────┐  │
│  │ fundamentals│  │ data_versions│ │ validation_logs             │  │
│  │ (quarterly) │  │ (DVC hashes)│  │ (quality audit trail)       │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────────┘  │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        BACKTESTING LAYER                            │
├─────────────────────────────────────────────────────────────────────┤
│  VectorBT (Apache 2.0)      │  bt (MIT, optional)                   │
│  • Vectorized execution     │  • Event-driven strategies            │
│  • Parameter optimization   │  • Order simulation                   │
│  • Monte Carlo simulation   │  • Commission modeling                │
│  • Portfolio analytics      │  • Walk-forward analysis              │
└─────────────────────────────────────────────────────────────────────┘
```

### Database Schema Additions

```sql
-- TimescaleDB hypertable for efficient time-series queries
CREATE TABLE daily_bars (
    symbol VARCHAR(10) NOT NULL,
    date DATE NOT NULL,
    open DECIMAL(12,4),
    high DECIMAL(12,4),
    low DECIMAL(12,4),
    close DECIMAL(12,4),
    volume BIGINT,
    adjusted_close DECIMAL(12,4),
    data_version VARCHAR(40),  -- DVC hash
    validated_at TIMESTAMP,
    PRIMARY KEY (symbol, date)
);
SELECT create_hypertable('daily_bars', 'date');

-- Corporate actions table
CREATE TABLE corporate_actions (
    id SERIAL PRIMARY KEY,
    symbol VARCHAR(10) NOT NULL,
    action_date DATE NOT NULL,
    action_type VARCHAR(20) NOT NULL,  -- 'split', 'dividend', 'delisting'
    ratio DECIMAL(10,6),               -- split ratio (2.0 = 2:1 split)
    amount DECIMAL(12,4),              -- dividend amount
    notes TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Data validation log
CREATE TABLE validation_logs (
    id SERIAL PRIMARY KEY,
    symbol VARCHAR(10),
    validation_date DATE,
    check_type VARCHAR(50),
    status VARCHAR(10),  -- 'pass', 'fail', 'warn'
    message TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Data version tracking
CREATE TABLE data_versions (
    id SERIAL PRIMARY KEY,
    table_name VARCHAR(50),
    version_hash VARCHAR(40),
    row_count BIGINT,
    date_range_start DATE,
    date_range_end DATE,
    created_at TIMESTAMP DEFAULT NOW()
);
```

### Validation Rules (Pandera Schema)

```python
import pandera as pa

daily_bar_schema = pa.DataFrameSchema({
    "symbol": pa.Column(str, pa.Check.str_length(1, 10)),
    "date": pa.Column("datetime64[ns]"),
    "open": pa.Column(float, pa.Check.greater_than(0)),
    "high": pa.Column(float, pa.Check.greater_than(0)),
    "low": pa.Column(float, pa.Check.greater_than(0)),
    "close": pa.Column(float, pa.Check.greater_than(0)),
    "volume": pa.Column(int, pa.Check.greater_than_or_equal_to(0)),
}, checks=[
    # High must be >= low
    pa.Check(lambda df: (df["high"] >= df["low"]).all()),
    # High must be >= open and close
    pa.Check(lambda df: (df["high"] >= df["open"]).all()),
    pa.Check(lambda df: (df["high"] >= df["close"]).all()),
    # Low must be <= open and close
    pa.Check(lambda df: (df["low"] <= df["open"]).all()),
    pa.Check(lambda df: (df["low"] <= df["close"]).all()),
    # No >100% single-day moves (likely bad data)
    pa.Check(lambda df: (abs(df["close"] / df["open"] - 1) < 1.0).all()),
])
```

### Pipeline Schedule (Airflow DAG)

```
┌────────────────────────────────────────────────────────┐
│  NIGHTLY DATA PIPELINE (2:00 AM ET)                    │
├────────────────────────────────────────────────────────┤
│  1. Fetch daily bars from Polygon.io                   │
│  2. Fetch corporate actions (splits, dividends)        │
│  3. Run validation checks                              │
│  4. Adjust historical prices for splits                │
│  5. Update fundamentals (weekly)                       │
│  6. Generate data version hash                         │
│  7. Log validation results                             │
│  8. Alert on validation failures                       │
└────────────────────────────────────────────────────────┘
```

## Consequences

### Positive
- **Reproducibility**: Data versions enable exact backtest reproduction
- **Reliability**: Validation prevents garbage-in-garbage-out
- **Accuracy**: Corporate actions ensure correct historical prices
- **Auditability**: Full trail of data changes and quality checks
- **Performance**: TimescaleDB optimized for time-series queries
- **Flexibility**: Dual backtesting engines for different use cases

### Negative
- **Complexity**: More components to install and maintain
- **Storage**: Historical data requires significant disk space
- **Learning curve**: Team must learn new tools (Airflow, Pandera)
- **Migration**: Existing flat files need conversion to PostgreSQL

### Mitigations
- Phased rollout: Start with validation, then versioning, then Airflow
- Documentation and runbooks for operations
- Retain flat file support as fallback during transition
- Use managed services where possible (TimescaleDB Cloud optional)

## Implementation Phases

### Phase 1: Data Validation (Week 1-2)
- Add Pandera schemas for daily/minute bars
- Implement validation checks in data ingestion
- Create validation_logs table
- Alert on validation failures

### Phase 2: Corporate Actions (Week 3-4)
- Create corporate_actions table
- Fetch splits/dividends from Polygon.io
- Implement price adjustment logic
- Backfill historical corporate actions

### Phase 3: TimescaleDB Migration (Week 5-6)
- Install TimescaleDB extension
- Migrate flat files to hypertables
- Update falcon-core DatabaseManager
- Benchmark query performance

### Phase 4: Data Versioning (Week 7-8)
- Integrate DVC for data lineage
- Create data_versions table
- Implement version hash generation
- Document reproduction workflow

### Phase 5: Pipeline Orchestration (Week 9-10)
- Deploy Airflow (or Prefect)
- Create nightly refresh DAG
- Set up monitoring and alerts
- Document operational runbooks

### Phase 6: Advanced Backtesting (Week 11-12)
- Integrate VectorBT for optimization
- Add Monte Carlo simulation
- Implement walk-forward analysis
- Create backtest result storage

## Open Source Alternatives Evaluated

### Backtesting Engines
| Tool | License | Pros | Cons | Decision |
|------|---------|------|------|----------|
| **VectorBT** | Apache 2.0 | Fast, vectorized, good visualization | Different paradigm than event-driven | **Primary choice** |
| **bt** | MIT | Simple, flexible, event-driven | Fewer features | Optional add-on |
| **Backtrader** | GPLv3 | Feature-rich, event-driven | GPL incompatible with ASL-2.0 distribution | Not included |
| **Lean/QuantConnect** | Apache 2.0 | Full-featured, live trading | Heavy, C# core | Not needed |

### Data Validation
| Tool | Pros | Cons | Decision |
|------|------|------|----------|
| **Pandera** | Pandas-native, lightweight | Limited ecosystem | Use for schemas |
| **Great Expectations** | Full-featured, UI | Heavy for our needs | Optional add-on |
| **Pydantic** | Fast, type hints | Not DataFrame-focused | Use for configs |

### Pipeline Orchestration
| Tool | Pros | Cons | Decision |
|------|------|------|----------|
| **Airflow** | Industry standard, mature | Complex setup | Primary choice |
| **Prefect** | Modern, easier setup | Newer, less docs | Alternative |
| **Dagster** | Good data lineage | Learning curve | Future consideration |
| **Cron + Scripts** | Simple | No monitoring/retry | Current state |

## References
- [VectorBT Documentation](https://vectorbt.dev/)
- [bt Documentation](https://pmorissette.github.io/bt/)
- [TimescaleDB Documentation](https://docs.timescale.com/)
- [Pandera Documentation](https://pandera.readthedocs.io/)
- [Apache Airflow Documentation](https://airflow.apache.org/docs/)
- [DVC Documentation](https://dvc.org/doc)
- [Hedge Fund Data Infrastructure (YouTube)](https://www.youtube.com/watch?v=PUgVZVe7VT4)

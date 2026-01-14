# ADR 0003: Multi-Profile Screener System

## Status
Accepted

## Date
2026-01-14

## Context

The original AI stock screener used a single hardcoded Finviz filter URL. This approach had limitations:
1. **No customization**: Users couldn't adjust filters without code changes
2. **Single strategy**: Couldn't run different screening approaches
3. **No performance tracking**: No way to measure which filters work best
4. **Limited scheduling**: All screens ran at the same times

Users wanted to:
- Run multiple screening strategies (momentum, earnings, seasonal)
- Track which profiles generate winning recommendations
- Adjust weights based on historical performance
- Export/import profiles as YAML for sharing

## Decision

Implement a database-driven multi-profile screener system with:

### Profile Structure
```yaml
name: "Momentum Breakouts"
theme: "momentum"
schedule:
  morning: true
  midday: true
  evening: false
finviz_filters:
  avgvol: "o750"      # >750K average volume
  price: "u20"        # Under $20
  relvol: "o1.5"      # Relative volume >1.5x
  change: "u"         # Up for the day
sector_focus:
  - Technology
  - "Consumer Cyclical"
weights:
  performance_5min: 0.35
  relative_volume: 0.30
  sector: 0.15
  rsi: 0.20
```

### Default Profiles
1. **Momentum Breakouts**: High relative volume, price action
2. **Earnings Plays**: Stocks with upcoming earnings
3. **Seasonal Sector Rotation**: Sector-based rotation strategy

### Database Schema
```sql
screener_profiles (
  id, name, description, theme,
  finviz_url, finviz_filters, sector_focus,
  schedule, weights, performance_score,
  enabled, created_at, updated_at
)

profile_runs (
  id, profile_id, run_type, run_timestamp,
  stocks_found, recommendations_generated,
  ai_agent, run_data
)

profile_performance (
  id, profile_id, date,
  stocks_recommended, stocks_profitable,
  avg_return_pct, attribution_breakdown,
  weight_adjustments, calculated_at
)
```

## Consequences

### Positive
- **Flexibility**: Users can create custom screening profiles
- **Measurability**: Track which profiles generate alpha
- **Adaptability**: Auto-adjust weights based on performance
- **Portability**: YAML export/import for sharing profiles
- **Scheduling**: Different profiles run at different times

### Negative
- **Complexity**: More database tables and code
- **Merge conflicts**: Multiple profiles may recommend same stock
- **Tuning overhead**: Users must understand weight parameters
- **API changes**: Dashboard needs new endpoints

### Mitigations
- Default profiles work out-of-box
- Merge algorithm deduplicates recommendations
- Documentation explains weight meanings
- API endpoints follow REST conventions

## Implementation

### CLI Usage
```bash
# Initialize default profiles
falcon-screener --init

# Run specific schedule
falcon-screener --run-type morning

# Run specific profile
falcon-screener --profile "Momentum Breakouts"
```

### API Endpoints
```
GET    /api/screener/profiles           # List all
POST   /api/screener/profiles           # Create
GET    /api/screener/profiles/<id>      # Get one
PUT    /api/screener/profiles/<id>      # Update
DELETE /api/screener/profiles/<id>      # Delete
POST   /api/screener/profiles/<id>/run  # Manual run
GET    /api/screener/profiles/export    # YAML export
POST   /api/screener/profiles/import    # YAML import
```

### Scheduled Execution
```
Morning (4:00 AM ET):  Pre-market scan
Midday (10:00 AM ET):  Mid-session opportunities
Evening (7:00 PM ET):  After-hours review
```

## Alternatives Considered

### 1. Config File Per Profile
- Pros: Simple, no database needed
- Cons: No performance tracking, manual management

### 2. Single Profile with Parameters
- Pros: Simpler code
- Cons: Can't compare strategies, limited flexibility

### 3. Machine Learning Profile Generation
- Pros: Automatic optimization
- Cons: Black box, requires training data, complexity

## References
- [Finviz Screener Documentation](https://finviz.com/help/screener.ashx)
- [falcon-screener Repository](https://github.com/TradingAsBuddies/falcon-screener)

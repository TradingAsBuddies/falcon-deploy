# Architectural Decision Records (ADRs)

This directory contains Architectural Decision Records for the Falcon Trading Platform.

## What is an ADR?

An Architectural Decision Record (ADR) is a document that captures an important architectural decision made along with its context and consequences.

## ADR Index

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [0001](0001-distributed-deployment-architecture.md) | Distributed Deployment Architecture | Accepted | 2026-01-14 |
| [0002](0002-postgresql-as-primary-database.md) | PostgreSQL as Primary Database | Accepted | 2026-01-14 |
| [0003](0003-multi-profile-screener-system.md) | Multi-Profile Screener System | Accepted | 2026-01-14 |
| [0004](0004-data-infrastructure-for-backtesting.md) | Data Infrastructure for Backtesting | Proposed | 2026-01-15 |

## ADR Template

When creating a new ADR, use this template:

```markdown
# ADR NNNN: Title

## Status
[Proposed | Accepted | Deprecated | Superseded]

## Date
YYYY-MM-DD

## Context
What is the issue that we're seeing that is motivating this decision?

## Decision
What is the change that we're proposing and/or doing?

## Consequences
What becomes easier or more difficult because of this change?

## Alternatives Considered
What other options were evaluated?

## References
Links to relevant documentation or resources.
```

## Contributing

1. Create a new file: `NNNN-short-title.md`
2. Use the template above
3. Submit for review
4. Update this README with the new entry

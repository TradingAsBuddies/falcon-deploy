# ADR 0001: Distributed Deployment Architecture

## Status
Accepted

## Date
2026-01-14

## Context

The Falcon Trading Platform was initially developed as a monolithic application running on a single Raspberry Pi. As the platform grew to include:
- AI-powered stock screening with multiple profiles
- Real-time market data processing
- Paper trading with position management
- YouTube strategy extraction and backtesting
- Web dashboard for monitoring

Several limitations became apparent:
1. **Storage constraints**: Market data flat files require significant storage (>20GB)
2. **Resource contention**: Screener, trader, and dashboard compete for CPU/memory
3. **Single point of failure**: All services on one node means total outage if it fails
4. **Scalability**: Cannot independently scale components based on demand

## Decision

Implement a 3-node distributed architecture with role-based separation:

### Node Topology

| Node | IP | Role | Services |
|------|-----|------|----------|
| falcon-db | 192.168.1.194 | Database | PostgreSQL |
| falcon-compute | 192.168.1.232 | Compute/Storage | falcon-screener, falcon-trader, market data |
| falcon-web | 192.168.1.162 | Web/Proxy | falcon-dashboard, nginx |

### Design Principles

1. **Separation of Concerns**: Each node has a distinct responsibility
2. **Data Locality**: High-throughput data processing near storage
3. **Stateless Web Tier**: Dashboard can be restarted without data loss
4. **Centralized Database**: Single source of truth for all services

### Communication Patterns

```
┌─────────────┐     HTTPS      ┌─────────────┐
│   Client    │───────────────▶│  falcon-web │
└─────────────┘                └──────┬──────┘
                                      │
                               PostgreSQL:5432
                                      │
┌─────────────┐                ┌──────▼──────┐
│falcon-compute│◀─────────────▶│  falcon-db  │
└─────────────┘  PostgreSQL    └─────────────┘
```

## Consequences

### Positive
- **Fault isolation**: Database failure doesn't crash web interface
- **Independent scaling**: Can add compute nodes for parallel screening
- **Resource optimization**: NVMe storage on compute node for market data
- **Security**: Database not exposed to public network
- **Maintainability**: Can update components independently

### Negative
- **Operational complexity**: Three nodes to monitor and maintain
- **Network dependency**: Services depend on network connectivity
- **Data synchronization**: Screener results must be copied to web node
- **Configuration management**: Secrets must be deployed to multiple nodes

### Mitigations
- Systemd services with auto-restart for resilience
- Health check endpoints for monitoring
- Centralized logging via journald
- Deployment scripts for consistent configuration

## Alternatives Considered

### 1. Single Node with Docker
- Pros: Simpler deployment, container isolation
- Cons: Still single point of failure, resource constraints remain

### 2. Kubernetes Cluster
- Pros: Auto-scaling, self-healing, declarative config
- Cons: Overkill for 3 Raspberry Pis, high learning curve

### 3. SQLite on Each Node
- Pros: No network dependency for database
- Cons: Data synchronization nightmare, no ACID across nodes

## Implementation Notes

### Directory Structure (FHS-compliant)
```
/opt/falcon/venv/          # Python virtual environment
/etc/falcon/secrets.env    # API keys and credentials
/var/lib/falcon/           # Data directory
/var/lib/falcon/market_data/  # Flat files (compute only)
/var/cache/falcon/         # Cache directory
/var/log/falcon/           # Log directory
```

### Service Management
```bash
# Deploy all nodes
./scripts/deploy.sh setup all

# Check status
./scripts/deploy.sh status all

# View logs
journalctl -u falcon-trader -f
```

## References
- [Falcon Deploy Repository](https://github.com/TradingAsBuddies/falcon-deploy)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Nginx Reverse Proxy](https://nginx.org/en/docs/)

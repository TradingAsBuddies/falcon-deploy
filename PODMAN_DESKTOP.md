# Falcon on Podman Desktop — Setup Guide

## Prerequisites

- **Podman Desktop** installed on Windows (v1.10+)
- **WSL2 integration** enabled for the `FedoraLinux-43` distro in Podman Desktop settings
- **gh CLI** installed and authenticated (`gh auth login`)
- Podman machine running (`podman machine start`)

---

## 1 — Clone and configure

```bash
gh repo clone TradingAsBuddies/falcon-deploy
cd falcon-deploy
cp .env.example .env
```

Open `.env` and fill in the required values:

| Variable | Required | Notes |
|---|---|---|
| `DB_PASSWORD` | Yes | Any strong password |
| `FINVIZ_API_KEY` | Yes | Needed by falcon-screener |
| `FALCON_DISCORD_WEBHOOK_URL` | Optional | For Discord notifications |
| `FALCON_BLUESKY_HANDLE` / `_APP_PASSWORD` | Optional | For Bluesky posts |

---

## 2 — Start the default stack

```bash
podman-compose up -d
```

This starts: `db`, `redis`, `falcon-screener`, `falcon-trader`, `falcon-messenger`.

Watch logs: `podman-compose logs -f falcon-trader`

---

## 3 — Access the services

| Service | URL |
|---|---|
| Falcon Trader dashboard | http://localhost:5000 |
| Messenger API | http://localhost:8080 |

`falcon-trader` has a 90-second start period; allow a moment before the dashboard responds.

---

## 4 — Optional profiles

### Monitoring (Prometheus + Grafana)

```bash
podman-compose --profile monitoring up -d
```

- Prometheus: http://localhost:9090
- Grafana: http://localhost:3000 (default login `admin`/`admin`)

Ensure `prometheus.yml` exists in the repo root before starting.

### Signal web + Traefik reverse proxy

```bash
podman-compose --profile web up -d
```

- Signal web: http://localhost:5001
- Traefik dashboard: http://localhost:8080 (port conflicts with messenger — run one or the other)

### All profiles at once

```bash
podman-compose --profile monitoring --profile web up -d
```

---

## 5 — SELinux note

All volume mounts in `podman-compose.yml` include the `:z` relabeling flag, which is required on FedoraLinux-43 with SELinux in enforcing mode. No manual `chcon` is needed.

---

## 6 — Podman socket path

The default socket path assumes uid `1000`. If your WSL2 user has a different uid, run:

```bash
echo /run/user/$(id -u)/podman/podman.sock
```

Update `PODMAN_SOCKET` in your `.env` with the output. The Traefik container uses this value to reach the Podman API.

---

## Stopping and cleanup

```bash
# Stop all services
podman-compose down

# Stop and remove volumes (destroys DB data)
podman-compose down -v
```

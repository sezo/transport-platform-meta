# infra — Claude context

## Purpose
Shared infrastructure stack. Every developer runs this before starting any service.
This is neutral ground — no single team owns it. Changes require architect approval.

## What runs here
All infrastructure containers. No application code. No business logic.

## Services

### PostgreSQL instances (one per service — failure isolated)
| Container | Port | Database | Owner |
|---|---|---|---|
| postgres-tickets | 5432 | tickets | Team 1 |
| postgres-vehicles | 5433 | vehicles | Team 2 — PostGIS enabled |
| postgres-accounting | 5434 | accounting | Team 3 |
| postgres-reporting | 5435 | readmodel | Reporting service |

### Message broker
- **RabbitMQ 3.13** — all inter-service events, saga coordination, outbox relay
- Management UI: http://localhost:15672
- Default credentials: transport / transport
- Vhost: / (single vhost for MVP, split per service in production)

### Identity
- **Keycloak 25** — JWT issuance, SSO, MFA, RBAC
- Admin console: http://localhost:9090
- Realm: transport
- Realm config imported from keycloak/realm-export.json on first start

### Cache
- **Redis 7** — shared cache layer, used by gateways and services
- maxmemory: 256mb, policy: allkeys-lru

### Observability stack (Grafana LGTM)
| Container | Purpose | Port |
|---|---|---|
| otel-collector | Receives OTel from all services, fans out | 4317 (gRPC) |
| grafana | Dashboards — single pane of glass | 3000 |
| loki | Log storage | internal |
| tempo | Trace storage | internal |
| prometheus | Metrics storage | internal |

Grafana anonymous access enabled for development.
Pre-built dashboards: service health, RabbitMQ throughput, PostgreSQL connections.

## Networks
- `transport-net` — named bridge network, internal: true
- All service docker-compose files attach to this network as external
- Only YARP gateways are exposed to host network

## First run
```bash
docker compose up -d
```
Images pulled automatically on first run (~2-3 min depending on connection).
Subsequent starts are instant from cache.

## Teardown
```bash
docker compose down          # stop containers, keep volumes
docker compose down -v       # stop containers, delete all data
```

## What NOT to do
- Do not add application containers here
- Do not expose PostgreSQL ports publicly in production
- Do not commit secrets or passwords to this repo
- Do not change the network name — all service repos depend on `transport-net`

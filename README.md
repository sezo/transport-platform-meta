# TransportPlatform

Enterprise business system for a major regional transport company.

## Prerequisites
- Docker Desktop 4.x+
- .NET 9 SDK
- Git

## Quick start

### 1. Start shared infrastructure (always first)
```bash
git clone https://github.com/TransportPlatform/_transport-platform-meta
cd _transport-platform-meta/infra
docker compose up -d
```

Wait ~30 seconds for all services to initialise, then verify:
- Keycloak: http://localhost:9090 (admin / admin)
- RabbitMQ: http://localhost:15672 (transport / transport)
- Grafana: http://localhost:3000

### 2. Start a service
```bash
git clone https://github.com/TransportPlatform/transport-platform-ticketing
cd transport-platform-ticketing
docker compose up -d
```

### 3. Test via Postman
Import the collection from `docs/postman/` and hit the service directly.
No gateway needed for local development.

## Port map
| Service | Port |
|---|---|
| YARP public gateway | 8080 |
| YARP internal gateway | 8081 |
| Ticketing service | 5001 |
| Vehicle service | 5003 |
| Accounting service | 5004 |
| Reporting service | 5005 |
| Keycloak | 9090 |
| RabbitMQ management | 15672 |
| Grafana | 3000 |
| PostgreSQL tickets | 5432 |
| PostgreSQL vehicles | 5433 |
| PostgreSQL accounting | 5434 |
| PostgreSQL reporting | 5435 |
| Redis | 6379 |

## Repo map
| Repo | Purpose |
|---|---|
| _transport-platform-meta | This repo — docs, infra, ADRs |
| transport-platform-contracts | Shared NuGet packages |
| transport-platform-gateway | YARP public + internal gateways |
| transport-platform-ticketing | Ticketing bounded context |
| transport-platform-vehicles | Vehicle + fleet bounded context |
| transport-platform-accounting | Accounting bounded context |
| transport-platform-reporting | CQRS read model + reporting API |
| transport-platform-integrations | External system adapters |

## Architecture overview
See [CLAUDE.md](./CLAUDE.md) for full architecture context.
See [docs/](./docs/) for C4 diagrams and ADRs.

## Technology stack
| Concern | Technology |
|---|---|
| Backend | .NET 9, C# |
| API gateway | YARP |
| Identity | Keycloak |
| Message broker | RabbitMQ + MassTransit |
| Database | PostgreSQL (per service) |
| Spatial | PostGIS (vehicles) |
| Cache | Redis |
| Observability | OpenTelemetry → Grafana LGTM |
| CI/CD | GitHub Actions + self-hosted runners |

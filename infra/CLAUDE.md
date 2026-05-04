# TransportPlatform — Claude context

## What this is
Enterprise business system for a major regional transport company (15,000+ employees).
Covers ticketing, fleet management, accounting, reporting, and external integrations.

## Architecture style
- Microservices — one service per bounded context, one team per service
- Clean Architecture (Onion) within each service
- Async-first — services communicate via RabbitMQ integration events
- CQRS — write model per service, shared read model via Reporting service
- Saga pattern (MassTransit) for distributed transactions
- Outbox pattern for guaranteed event delivery

## Repo map (GitHub organisation: TransportPlatform)
| Repo | Owner | Purpose |
|---|---|---|
| _transport-platform-meta | Architect | Docs, infra, ADRs — this repo |
| transport-platform-contracts | All teams | Shared NuGet: events, DTOs, common infra |
| transport-platform-gateway | Architect | YARP public + internal gateways |
| transport-platform-ticketing | Team 1 | Ticket purchase, validation, saga |
| transport-platform-vehicles | Team 2 | Fleet management, GPS, PostGIS |
| transport-platform-accounting | Team 3 | Invoicing, payments, fiscal |
| transport-platform-reporting | Team 1+EM | CQRS read model, projectors, query API |
| transport-platform-integrations | All teams | External system adapters |

## Bounded contexts
- **Ticketing** — ticket lifecycle, reservations, validation, capacity
- **Vehicle** — fleet, GPS positioning, driver assignment, routes
- **Accounting** — invoices, payments, fiscal compliance, payroll
- **Reporting** — cross-context read model, dashboards, analytics

## Key architectural decisions
See docs/adr/ for full rationale. Summary:
- RabbitMQ over Kafka (simpler ops for MVP, sufficient throughput)
- YARP over Kong/Nginx (native .NET, C# programmable)
- Separate PostgreSQL per service (failure isolation, independent scaling)
- PostGIS on vehicles DB (spatial queries, geofencing, route geometry)
- MassTransit for sagas and outbox (free OSS, .NET native)
- Keycloak for identity (SSO, JWT, MFA, RBAC — free OSS)
- Grafana LGTM stack for observability (OTel → Loki/Tempo/Prometheus)
- GitHub + self-hosted runners for CI/CD (cloud UI, on-prem compute)
- Modified trunk-based development (feature branches max 5 days)

## Cross-cutting concerns
- **Auth** — YARP validates user JWT, injects X-User-Id/X-User-Roles headers, replaces with M2M token. Services never validate user tokens directly.
- **Observability** — every service calls AddTransportObservability() from Transport.Infrastructure.Common. OTel collector fans out to Loki (logs), Tempo (traces), Prometheus (metrics).
- **Outbox** — every service uses outbox pattern. Domain changes and event publication in one DB transaction.
- **Saga** — distributed transactions coordinated via MassTransit state machines. Compensation on failure.

## What NOT to do
- Never put business logic in integration adapters (integrations/ folder)
- Never share a PostgreSQL instance between services
- Never call another service's database directly
- Never put domain concepts in Transport.Contracts (events and DTOs only)
- Never forward user JWT tokens between services (use M2M + header propagation)
- Never merge to main with failing CI

## Team structure
- 3 Scrum teams, ~3 years delivery
- Sector-by-sector: Ticketing first, then Vehicles, then Accounting, then remaining sectors
- Each team owns their repo, their DB, their deployment cadence
- Contracts repo requires approval from all team leads before merge

## Running locally
1. Clone _transport-platform-meta
2. cd infra && docker compose up -d
3. Clone whichever service repo you need
4. cd into it && docker compose up -d
5. Hit localhost:{port} directly via Postman
See infra/README.md for port map.

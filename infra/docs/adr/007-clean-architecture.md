# ADR 007 — Clean Architecture per service

**Status:** Accepted
**Date:** 2025-05

## Decision
Clean Architecture (Onion) within each service. Four layers per service:
Domain → Application → Infrastructure → API

## Layer rules
| Layer | Dependencies | Contains |
|---|---|---|
| Domain | None | Entities, value objects, domain events, business rules |
| Application | Domain only | Commands, queries, sagas, interfaces |
| Infrastructure | Application | EF Core, RabbitMQ, Redis, outbox, external clients |
| API | Application | Controllers, middleware, DI wiring, Program.cs |

## Rationale
- Domain has zero NuGet dependencies — pure C#, fast unit tests
- Infrastructure is a detail — swap EF for Dapper without touching domain
- Clear boundaries prevent accidental coupling between layers
- Consistent structure across all 3 service teams — lower cognitive overhead
- CQRS within Application layer — commands and queries separated

## Why not Vertical Slice
Vertical Slice works well when features are fully independent. In this domain,
ReserveTicket, CancelTicket, ValidateTicket all touch the same Ticket aggregate.
Slicing vertically creates cross-slice dependencies or domain duplication.
Clean Architecture keeps the domain coherent.

## Consequences
- More projects per solution than a simple 3-layer architecture
- Worth it for a 3-year, 3-team project where the domain will grow significantly

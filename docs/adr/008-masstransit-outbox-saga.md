# ADR 008 — MassTransit for outbox and sagas

**Status:** Accepted
**Date:** 2025-05

## Decision
MassTransit as the messaging abstraction over RabbitMQ, used for:
- Outbox pattern (guaranteed event delivery)
- Saga state machines (distributed transaction coordination)
- Consumer registration and retry policies

## Rationale
- Free OSS (MIT licence) — no cost, NuGet package only
- Native .NET — no separate process or sidecar
- Built-in outbox with EF Core — saves significant custom code
- Saga state machines — declarative, testable, persisted to PostgreSQL
- Abstracts RabbitMQ — can swap transport if needed
- Active community, excellent documentation

## Outbox pattern
Every service that publishes events uses the MassTransit outbox:
- Domain change + outbox message in one EF Core transaction
- Background relay publishes to RabbitMQ after commit
- Guarantees at-least-once delivery even if broker is temporarily down

## Saga pattern
Ticket purchase saga spans Ticketing + Accounting + Vehicle:
- MassTransit state machine defines states and transitions
- Saga state persisted to PostgreSQL via EF Core
- Compensation events triggered automatically on failure

## Consequences
- MassTransit adds learning curve for developers unfamiliar with it
- Worth it — eliminates ~500 lines of custom outbox + retry code per service
- Wolverine is a strong alternative with similar features, considered but MassTransit
  has wider adoption and more Stack Overflow answers

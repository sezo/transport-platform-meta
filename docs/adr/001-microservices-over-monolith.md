# ADR 001 — Microservices over monolith

**Status:** Accepted
**Date:** 2025-05
**Deciders:** Solution architect, EM

## Context
15,000+ employee transport company. 8 sectors to be delivered sector-by-sector over 3 years.
3 Scrum teams working in parallel. Each sector has distinct domain logic and independent
deployment needs. Heavy external integrations per sector.

## Decision
Three core microservices for MVP (Ticketing, Vehicle, Accounting) with a separate
Reporting service and integration adapters per external domain.

Each service:
- Has its own git repository
- Has its own PostgreSQL database
- Has its own deployment pipeline
- Is owned by one Scrum team

## Rationale
- Sector-by-sector delivery maps naturally to service boundaries
- Teams can release independently without coordinating deployments
- Failure in one service does not cascade to others
- Services can be scaled independently (Ticketing expects highest load)
- Clean bounded context enforcement at the tooling level, not just convention

## Consequences
- Distributed transaction complexity — mitigated by Saga + Outbox patterns
- Operational overhead — mitigated by shared infra stack and Docker Compose
- Network latency for inter-service calls — mitigated by async-first event communication
- More repos to manage — mitigated by GitHub organisation structure

## Rejected alternatives
- **Modular monolith** — rejected because independent deployment per team is a hard requirement
- **Single monolith** — rejected immediately, does not scale to 3 teams over 3 years

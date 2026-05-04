# ADR 005 — Separate PostgreSQL instance per service

**Status:** Accepted
**Date:** 2025-05
**Deciders:** Solution architect, EM

## Decision
Each service has its own PostgreSQL instance. No shared databases.

## Rationale
- **Failure isolation** — accounting DB going down does not affect ticket sales
- **Independent scaling** — ticketing DB can get more RAM without touching others
- **Independent migrations** — Team 1 schema changes never risk Team 2's data
- **Zero cost argument** — PostgreSQL is free, no licensing reason to share
- **Enforces bounded context** — teams cannot query each other's data directly

## PostgreSQL instances
| Instance | Port | Notes |
|---|---|---|
| postgres-tickets | 5432 | Standard PostgreSQL 16 |
| postgres-vehicles | 5433 | PostGIS 16-3.4 — spatial queries, GPS |
| postgres-accounting | 5434 | Standard PostgreSQL 16 |
| postgres-reporting | 5435 | Standard PostgreSQL 16 — read model only |

## PostGIS note
Vehicle service requires PostGIS for:
- Storing GPS coordinates as geometry types
- Nearest vehicle queries (ST_Distance)
- Geofencing (ST_Within)
- Route geometry storage and queries

## Consequences
- More containers to manage — acceptable with Docker Compose
- Cross-service queries impossible at DB level — by design, use read model
- Backup strategy needed per instance — document in ops runbook

## Rejected alternatives
- **One PostgreSQL, separate schemas** — schema changes can still affect other services,
  single point of failure remains
- **One PostgreSQL, separate databases** — still single point of failure at server level

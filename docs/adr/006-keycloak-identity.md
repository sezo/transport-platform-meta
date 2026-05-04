# ADR 006 — Keycloak for identity

**Status:** Accepted
**Date:** 2025-05

## Decision
Keycloak as the identity provider for all clients and services.

## Rationale
- Free OSS — no per-user licensing cost (15,000 employees matters here)
- SSO across all clients — B2C, B2B, admin, mobile, devices — single login
- MFA out of the box — required for admin, inspector, and device accounts
- RBAC — fine-grained roles per client
- Standard protocols — OAuth2, OIDC, SAML — integrates with anything
- Self-hosted — runs on client hardware, data never leaves premises
- M2M client credentials flow — service-to-service auth without user tokens

## Realm structure
Single realm: `transport`
Separate clients per surface: b2c-web, b2b-web, admin-web, mobile-app,
public-gateway, internal-gateway, and one per service (M2M).

## Consequences
- Keycloak is operationally non-trivial in production (HA setup, DB backup)
- For MVP single instance is acceptable
- Production: Keycloak cluster with dedicated PostgreSQL instance (not shared with services)

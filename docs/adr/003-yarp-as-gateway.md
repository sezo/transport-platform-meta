# ADR 003 — YARP as API gateway

**Status:** Accepted
**Date:** 2025-05
**Deciders:** Solution architect, EM

## Context
Need an API gateway for routing, auth, and rate limiting. Two gateways required:
public (internet-facing) and internal (VPN-only for devices and inspectors).

## Decision
YARP (Yet Another Reverse Proxy) for both gateways.

## Rationale
- Native .NET — gateway logic written in C#, same language as all teams
- Fully programmable middleware pipeline — user context header injection in C#
- Built-in load balancing with LeastRequests policy for Ticketing instances
- Active health checks — automatic failover if a service instance goes down
- Free OSS — Microsoft-maintained, strong community
- Teams don't need to learn Lua (Nginx) or a separate DSL

## Dual gateway pattern
Two separate YARP instances enforce network-level separation:
- Public gateway — HTTPS, aggressive rate limiting, JWT validation
- Internal gateway — VPN-required, higher trust, device/inspector endpoints only

If public gateway is compromised, internal endpoints are unreachable.
One gateway with two route groups would give config isolation but not process isolation.

## Consequences
- YARP is newer than Nginx (2021) — less battle-hardened at the edge
- Mitigated by placing Nginx in front of YARP for TLS termination if needed in production

## Rejected alternatives
- **Kong** — powerful but adds Lua plugins and separate config layer, overkill for MVP
- **Nginx** — not programmable in C#, awkward JWT claim extraction
- **Ocelot** — older, less momentum than YARP, similar feature set

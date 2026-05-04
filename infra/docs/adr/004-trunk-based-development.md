# ADR 004 — Modified trunk-based development

**Status:** Accepted
**Date:** 2025-05
**Deciders:** EM, team leads

## Decision
Modified trunk-based development across all repos:
- `main` branch is always deployable
- Feature branches allowed, maximum lifetime 5 days
- PRs required before merge to main
- CI must pass before merge — non-negotiable
- Feature flags for incomplete or risky changes

## Branch lifetime rules
| Repo | Max branch lifetime | Approvals required |
|---|---|---|
| transport-platform-contracts | 2 days | All 3 team leads |
| transport-platform-gateway | 3 days | Architect |
| Service repos (ticketing, vehicles, accounting) | 5 days | Team lead |
| transport-platform-reporting | 5 days | EM |
| transport-platform-integrations | 5 days | Team lead |

## Rationale
- Long-lived branches are the root cause of merge conflicts, not branches themselves
- 5-day limit forces small, incremental commits
- PRs stay small enough to actually review
- CI on every merge catches integration issues early
- Independent repos mean teams don't block each other even on shared CI

## Feature flags
Simple appsettings.json flags for MVP:
```json
"FeatureFlags": {
  "NewFiscalizationFlow": false,
  "NaturalLanguageReporting": false
}
```
Inject IOptions<FeatureFlags> where needed. No external flag service for MVP.

## Consequences
- Requires discipline — EM enforces branch lifetime rules in sprint reviews
- Junior devs may find short-lived branches uncomfortable initially
- Investment in CI pipelines upfront pays off quickly

# ADR 002 — RabbitMQ over Kafka

**Status:** Accepted
**Date:** 2025-05
**Deciders:** Solution architect, EM

## Context
Services need reliable async communication. Two main options evaluated: RabbitMQ and Kafka.

## Decision
RabbitMQ with MassTransit for all inter-service event communication.

## Rationale
- Simpler operational model — no ZooKeeper/KRaft cluster to manage on-prem
- MassTransit provides saga, outbox, and retry out of the box on top of RabbitMQ
- Sufficient throughput for transport domain (not a high-frequency trading system)
- 3 dev teams can reason about queues and exchanges more easily than partitions and offsets
- On-prem deployment on client hardware — RabbitMQ has lower resource requirements

## Consequences
- No event replay out of the box (Kafka's killer feature for event sourcing)
- If full event sourcing is needed for Accounting (audit trail), revisit this decision
- Message ordering is per-queue, not globally ordered — acceptable for this domain

## Rejected alternatives
- **Kafka** — operationally heavier, overkill for MVP throughput requirements
- **Azure Service Bus / AWS SQS** — client hardware is on-prem, cloud messaging ruled out

## Future consideration
If GPS telemetry volume grows significantly (1000+ vehicles, sub-second pings),
evaluate a dedicated MQTT broker for vehicle position ingestion, keeping RabbitMQ
for business events only.

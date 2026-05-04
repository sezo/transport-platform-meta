# Infrastructure

Shared infrastructure stack for local development.
Run this first before starting any service.

## Start
```bash
docker compose up -d
```

## Stop
```bash
docker compose down
```

## Verify everything is running
```bash
docker compose ps
```

All containers should show `Up` or `healthy`.

## Service URLs
| Service | URL | Credentials |
|---|---|---|
| Keycloak admin | http://localhost:9090 | admin / admin |
| RabbitMQ management | http://localhost:15672 | transport / transport |
| Grafana | http://localhost:3000 | anonymous |

## Troubleshooting

### Port already in use
Check what's using the port: `lsof -i :5432` (Mac/Linux) or `netstat -ano | findstr :5432` (Windows).
Stop the conflicting process or change the port in docker-compose.yml.

### Keycloak not starting
First run takes ~60 seconds. Check logs: `docker compose logs keycloak`.

### Service can't connect to postgres/rabbitmq
Ensure infra is running before starting service containers.
The `transport-net` network must exist: `docker network ls | grep transport`.

## Resetting data
```bash
docker compose down -v
docker compose up -d
```
This wipes all database data, RabbitMQ queues, and Keycloak config.
Keycloak realm will be re-imported from keycloak/realm-export.json.

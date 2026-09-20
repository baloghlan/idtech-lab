# IDTECH Docker Application

A simple Dockerized application that uses Redis to store visit counts.

## Build

Build the application Docker image:

```bash
docker build -t idtech-portal:1.0 .
```

## Run

Run the application directly with Docker:

```bash
docker run -d \
  --name idtech-portal-app \
  -p 8080:5000 \
  idtech-portal:1.0
```

## Docker Compose

Start the application and Redis in the background:

```bash
docker compose up -d
```

Check running services:

```bash
docker compose ps
```

View logs:

```bash
docker compose logs
```

Stop the services:

```bash
docker compose down
```

Start them again:

```bash
docker compose up -d
```

The Redis data is stored in the `idtech-redis-data` named volume, so the visit counter persists when the containers are stopped and recreated.

## Problem and Solution

### Visit Counter Resets After Restart

Initially, the visit counter would reset when the Redis container was removed or recreated because Redis data was stored only inside the container.

**Solution:** Use a named Docker volume to persist Redis data:

```yaml
services:
  redis:
    image: redis:7-alpine
    volumes:
      - idtech-redis-data:/data

volumes:
  idtech-redis-data:
```

With the named volume, Redis data survives container removal and recreation, so the visit counter continues from its previous value.

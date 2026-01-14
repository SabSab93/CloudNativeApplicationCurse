# PLAN_BLUE_GREEN.md — Blue/Green Deployment Strategy (TP5)

## Goal
Deploy a new version of the application **without stopping the current one**, and switch traffic using a **reverse proxy (Nginx)**.
Rollback must be **near-instant**.

---

## Architecture Overview

### Components
- **PostgreSQL (single instance)**: shared by both versions (blue/green)
- **Frontend + Backend BLUE**: runs in parallel with GREEN
- **Frontend + Backend GREEN**: runs in parallel with BLUE
- **Nginx reverse proxy**: only entry point for users, routes traffic to BLUE or GREEN

### Naming
- backend: `app-back-blue`, `app-back-green`
- frontend: `app-front-blue`, `app-front-green`
- proxy: `reverse-proxy`
- database: `postgres`

---

## Docker Compose Files

We split responsibilities to avoid touching unintended services:

1) `docker-compose.base.yml`
- Contains only **Postgres** + shared network + volumes

2) `docker-compose.blue.yml`
- Contains **frontend-blue + backend-blue**
- Uses images tagged for BLUE (e.g. `${IMAGE_TAG}`)
- Connected to the shared network

3) `docker-compose.green.yml`
- Contains **frontend-green + backend-green**
- Uses images tagged for GREEN (e.g. `${IMAGE_TAG}`)
- Connected to the shared network

4) `docker-compose.proxy.yml`
- Contains **Nginx reverse proxy**
- Mounts a config file that selects the active color
- Connected to the shared network
- Exposes public ports (e.g. 8080 -> 80)

---

## How to start the full environment

### First boot
```bash
docker compose -f docker-compose.base.yml up -d
docker compose -f docker-compose.blue.yml up -d
docker compose -f docker-compose.proxy.yml up -d
```

At this point, **BLUE is live**.

### Running both versions (optional)
```bash
docker compose -f docker-compose.green.yml up -d
```

---

## Traffic routing (Nginx)

### Routing principle
Nginx forwards:
- `/` to the active frontend (blue or green)
- `/api` to the active backend (blue or green)

### Switching mechanism
A single file mounted into the proxy container defines the active color:

- `nginx/conf.d/active.conf`

Switch procedure:
1. Update `active.conf` to target the inactive color
2. Reload Nginx without stopping the container:
```bash
docker exec reverse-proxy nginx -s reload
```

---

## Deployment Scenario

### Initial state
- Active color: **BLUE**
- Proxy routes traffic to BLUE
- GREEN is inactive or running without traffic

### Deploying a new version
1. Identify inactive color:
   - If BLUE is active → deploy to GREEN
   - If GREEN is active → deploy to BLUE

2. Deploy new version on inactive color:
```bash
IMAGE_TAG=<new_sha> docker compose -f docker-compose.green.yml up -d
```

3. Perform health checks on inactive stack

4. Switch proxy to the new color:
```bash
docker exec reverse-proxy nginx -s reload
```

Now the new version is live.

---

## Rollback Scenario (near-instant)

If the new version is unstable:
1. Update `active.conf` back to the previous color
2. Reload Nginx:
```bash
docker exec reverse-proxy nginx -s reload
```

Traffic is immediately restored to the previous stable version.

---

## Why this plan is safe

- Docker Compose files are separated by responsibility
- Updating one color does not impact the other
- Reverse proxy is isolated from application logic
- Database is shared and never restarted
- Rollback requires only a proxy reload

# k8s-app

A Kubernetes-native key-value store with a React UI and REST API. Enter numeric IDs with text values, view the full list, and toggle request logging — all backed by Redis with persistent storage.

## Architecture

```
Browser
  │ HTTP :80
  ▼
frontend (React + nginx)
  └── /api/* proxied to →
backend (Node.js / Express)
  └── Redis commands →
redis (Redis 7, RDB persistence)
  └── PersistentVolume
```

Three microservices, each in its own Kubernetes Deployment:

| Service  | Image base   | Port | Exposed |
|----------|--------------|------|---------|
| frontend | nginx:alpine | 80   | Yes (LoadBalancer) |
| backend  | node:20-alpine | 3000 | No (ClusterIP) |
| redis    | redis:7-alpine | 6379 | No (ClusterIP) |

## REST API

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/health` | Health check |
| GET | `/api/entries` | List all entries |
| POST | `/api/entries` | Create `{ id: number, value: string }` |
| GET | `/api/entries/:id` | Get by ID |
| DELETE | `/api/entries/:id` | Delete by ID |
| GET | `/api/logging/status` | Get logging state |
| POST | `/api/logging/toggle` | Toggle request logging on/off |

All responses include a `"logging": bool` field reflecting the current logging state.

---

## Deployment Options

### Option 1 — Vanilla (Local, Docker Desktop)

Builds images locally and deploys to Docker Desktop's built-in Kubernetes. No registry, no cloud account needed.

**Prerequisites:** Docker Desktop with Kubernetes enabled (`Settings → Kubernetes → Enable Kubernetes`).

```bash
./scripts/deploy.sh vanilla
```

App available at **http://localhost**.

Full instructions: [docs/local-setup.md](docs/local-setup.md)

---

### Option 2 — GitHub Actions + GHCR

Pushes images to GitHub Container Registry automatically on every push to `main`. No manual image builds or registry setup needed.

**Prerequisites:** A GitHub repository with the workflow committed.

The workflow at `.github/workflows/build-push.yml` runs automatically. It uses the built-in `GITHUB_TOKEN` — no secrets to configure.

Images produced:
```
ghcr.io/<your-username>/k8s-app/backend:latest
ghcr.io/<your-username>/k8s-app/frontend:latest
```

Full instructions: [docs/ci-setup.md](docs/ci-setup.md)

---

### Option 3 — AWS (EKS)

Deploys to an EKS cluster using GHCR images built by CI. Redis is backed by an EBS gp3 volume.

**Prerequisites:** AWS CLI, `eksctl`, `kubectl`, and GHCR images already pushed (run Option 2 first).

```bash
cp config.env.example config.env
# Edit config.env with your values
./scripts/deploy.sh aws
```

Full instructions: [docs/aws-setup.md](docs/aws-setup.md)

---

## Configuration

All configurable parameters live in `config.env` (copied from `config.env.example`). Required for Option 3 (AWS); not needed for vanilla or CI builds.

| Variable | Description | Default |
|----------|-------------|---------|
| `GITHUB_OWNER` | GitHub username/org for GHCR image references | — |
| `IMAGE_TAG` | Image tag to deploy (`latest` or a Git SHA) | `latest` |
| `AWS_REGION` | AWS region for EKS cluster | `us-east-1` |
| `EKS_CLUSTER_NAME` | Name of the EKS cluster | `k8s-app` |
| `NODE_TYPE` | EC2 instance type for worker nodes | `t3.medium` |
| `NODE_COUNT` | Initial node count | `2` |
| `NODE_MIN` | Minimum nodes (autoscaling) | `1` |
| `NODE_MAX` | Maximum nodes (autoscaling) | `3` |

---

## Deploy Script

```
./scripts/deploy.sh <option>

  vanilla   Build images locally and deploy to Docker Desktop K8s
  aws       Deploy to EKS using GHCR images (reads config.env)
  teardown  Remove all k8s-app resources from the current context
```

## Project Structure

```
.
├── config.env.example       # Configuration template — copy to config.env
├── scripts/
│   └── deploy.sh            # Deployment script (vanilla | aws | teardown)
├── frontend/                # React app + nginx
│   ├── src/
│   ├── Dockerfile
│   ├── nginx.conf
│   └── vite.config.js
├── backend/                 # Node.js / Express API
│   ├── src/
│   └── Dockerfile
├── k8s/
│   ├── local/               # Manifests for vanilla (Docker Desktop)
│   │   ├── namespace.yaml
│   │   ├── redis/
│   │   ├── backend/
│   │   └── frontend/
│   └── aws/                 # Manifests for AWS (EKS)
│       ├── storageclass.yaml
│       ├── redis/
│       ├── backend/
│       └── frontend/
├── .github/
│   └── workflows/
│       └── build-push.yml   # CI: build + push to GHCR on push to main
└── docs/
    ├── local-setup.md       # Vanilla deployment guide
    ├── ci-setup.md          # GitHub Actions + GHCR guide
    └── aws-setup.md         # EKS deployment guide
```

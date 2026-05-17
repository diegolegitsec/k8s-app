# Option 1 — Vanilla (Local, Docker Desktop)

Builds images locally and deploys to Docker Desktop's built-in Kubernetes cluster. No registry or cloud account required.

## Prerequisites

- Docker Desktop for Mac with Kubernetes enabled
  - Open Docker Desktop → Settings → Kubernetes → Enable Kubernetes → Apply & Restart
- `kubectl` (bundled with Docker Desktop)

## Deploy

```bash
./scripts/deploy.sh vanilla
```

The script:
1. Builds `k8s-app/backend:latest` and `k8s-app/frontend:latest` locally
2. Applies all manifests in `k8s/local/`
3. Waits for deployments to roll out
4. Prints the app URL

App available at **http://localhost**.

## Verify

```bash
# Health check
curl http://localhost/api/health

# Create an entry
curl -X POST http://localhost/api/entries \
  -H "Content-Type: application/json" \
  -d '{"id": 1, "value": "hello world"}'

# List all entries
curl http://localhost/api/entries

# Toggle logging
curl -X POST http://localhost/api/logging/toggle
```

## Rebuild After Code Changes

```bash
./scripts/deploy.sh vanilla
```

Re-running the script rebuilds both images and does a rolling restart.

To restart a single service after a rebuild:
```bash
docker build -t k8s-app/backend:latest ./backend
kubectl rollout restart deployment/backend -n k8s-app
```

## Tear Down

```bash
./scripts/deploy.sh teardown
```

## Manual Apply (without the script)

If you prefer to apply manifests directly:

```bash
kubectl apply -f k8s/local/namespace.yaml
kubectl apply -f k8s/local/redis/
kubectl apply -f k8s/local/backend/
kubectl apply -f k8s/local/frontend/
```

## Troubleshooting

**Pods stuck in `ErrImagePull`**
The `imagePullPolicy: Never` in local manifests requires the image to exist locally.
Make sure you ran `docker build` before applying, or use `./scripts/deploy.sh vanilla` which handles both steps.

**Backend in `CrashLoopBackOff`**
Redis may still be starting. Check pod status:
```bash
kubectl get pods -n k8s-app
kubectl logs -n k8s-app deployment/backend
```
The backend reconnects automatically once Redis is ready.

**`localhost` not responding**
```bash
kubectl get svc frontend-service -n k8s-app
```
EXTERNAL-IP should be `localhost`. If it shows `<pending>`, wait a moment — Docker Desktop takes a few seconds to assign it.

# Local Setup — Docker Desktop Kubernetes

## Prerequisites

- Docker Desktop for Mac with Kubernetes enabled
  - Open Docker Desktop → Settings → Kubernetes → Enable Kubernetes → Apply & Restart
- `kubectl` (comes with Docker Desktop)

## 1. Build Docker Images

Run from the repo root. The `imagePullPolicy: Never` in the manifests means K8s uses these local images directly — no registry needed.

```bash
docker build -t k8s-app/backend:latest ./backend
docker build -t k8s-app/frontend:latest ./frontend
```

## 2. Deploy

```bash
# Namespace first
kubectl apply -f k8s/local/namespace.yaml

# Redis (PV must be created before PVC)
kubectl apply -f k8s/local/redis/pv.yaml
kubectl apply -f k8s/local/redis/pvc.yaml
kubectl apply -f k8s/local/redis/deployment.yaml
kubectl apply -f k8s/local/redis/service.yaml

# Backend
kubectl apply -f k8s/local/backend/configmap.yaml
kubectl apply -f k8s/local/backend/deployment.yaml
kubectl apply -f k8s/local/backend/service.yaml

# Frontend
kubectl apply -f k8s/local/frontend/deployment.yaml
kubectl apply -f k8s/local/frontend/service.yaml
```

Or apply whole directories at once (order matters for Redis PV/PVC):

```bash
kubectl apply -f k8s/local/namespace.yaml
kubectl apply -f k8s/local/redis/
kubectl apply -f k8s/local/backend/
kubectl apply -f k8s/local/frontend/
```

## 3. Wait for Rollout

```bash
kubectl rollout status deployment/redis   -n k8s-app
kubectl rollout status deployment/backend -n k8s-app
kubectl rollout status deployment/frontend -n k8s-app
```

## 4. Access the App

Docker Desktop automatically assigns `localhost` as the EXTERNAL-IP for LoadBalancer services.

- **UI:** http://localhost
- **API:** http://localhost/api/entries

## 5. Verify

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

# Check logging state
curl http://localhost/api/logging/status
```

## 6. Tear Down

```bash
kubectl delete namespace k8s-app
kubectl delete pv redis-pv
```

## Rebuild After Code Changes

```bash
docker build -t k8s-app/backend:latest ./backend
kubectl rollout restart deployment/backend -n k8s-app

docker build -t k8s-app/frontend:latest ./frontend
kubectl rollout restart deployment/frontend -n k8s-app
```

## Troubleshooting

**Pods stuck in `ErrImagePull` or `ImagePullBackOff`**
Make sure `imagePullPolicy: Never` is set in the deployment YAML and the image tag matches exactly what you built (`k8s-app/backend:latest`).

**Backend pods in `CrashLoopBackOff`**
Redis may not be ready yet. Check Redis pod status:
```bash
kubectl get pods -n k8s-app
kubectl logs -n k8s-app deployment/backend
```
The backend reconnects automatically once Redis is available.

**`localhost` not responding**
```bash
kubectl get svc frontend-service -n k8s-app
```
The EXTERNAL-IP should show `localhost`. If it shows `<pending>`, Kubernetes is still assigning it — wait a moment.

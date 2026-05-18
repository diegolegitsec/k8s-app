#!/usr/bin/env bash
# Deploys the stack to Docker Desktop's built-in Kubernetes cluster.
# Uses pre-built images from GHCR — no local docker build needed.
#
# Usage:
#   ./scripts/small.sh start    — deploy to Docker Desktop K8s
#   ./scripts/small.sh stop     — remove all resources
#   ./scripts/small.sh restart  — stop then start
#   ./scripts/small.sh logs     — tail logs from all deployments

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NS=k8s-app

BACKEND_IMAGE=ghcr.io/diegolegitsec/k8s-app/backend:latest
FRONTEND_IMAGE=ghcr.io/diegolegitsec/k8s-app/frontend:latest

log() { echo "▶  $*"; }

# Apply a local manifest but swap in the GHCR images and set imagePullPolicy to Always.
apply() {
    sed \
        -e "s|image: k8s-app/backend:latest|image: $BACKEND_IMAGE|g" \
        -e "s|image: k8s-app/frontend:latest|image: $FRONTEND_IMAGE|g" \
        -e "s|imagePullPolicy: Never|imagePullPolicy: IfNotPresent|g" \
        "$1" | kubectl apply -f -
}

start() {
    log "Pulling images..."
    docker pull "$BACKEND_IMAGE"
    docker pull "$FRONTEND_IMAGE"

    log "Creating namespace..."
    kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

    log "Applying Redis..."
    kubectl apply -f "$ROOT/k8s/local/redis/pv.yaml"
    kubectl apply -f "$ROOT/k8s/local/redis/pvc.yaml"
    kubectl apply -f "$ROOT/k8s/local/redis/secret.yaml"
    kubectl apply -f "$ROOT/k8s/local/redis/deployment.yaml"
    kubectl apply -f "$ROOT/k8s/local/redis/service.yaml"

    log "Applying backend..."
    kubectl apply -f "$ROOT/k8s/local/backend/configmap.yaml"
    apply "$ROOT/k8s/local/backend/deployment.yaml"
    kubectl apply -f "$ROOT/k8s/local/backend/service.yaml"

    log "Applying frontend..."
    apply "$ROOT/k8s/local/frontend/deployment.yaml"
    kubectl apply -f "$ROOT/k8s/local/frontend/service.yaml"

    log "Applying network policies..."
    kubectl apply -f "$ROOT/k8s/local/network-policies.yaml"

    log "Waiting for rollout..."
    kubectl rollout status deployment/redis    -n "$NS"
    kubectl rollout status deployment/backend  -n "$NS"
    kubectl rollout status deployment/frontend -n "$NS"

    echo ""
    echo "✔  App running at http://localhost"
    echo "   API:  http://localhost/api/entries"
    echo ""
    echo "   Stop with: ./scripts/small.sh stop"
}

stop() {
    log "Deleting namespace $NS..."
    kubectl delete namespace "$NS" --ignore-not-found

    log "Deleting PersistentVolume redis-pv..."
    kubectl delete pv redis-pv --ignore-not-found

    echo "✔  Stopped."
}

logs() {
    kubectl logs -f -n "$NS" deployment/backend  --prefix &
    kubectl logs -f -n "$NS" deployment/frontend --prefix &
    kubectl logs -f -n "$NS" deployment/redis    --prefix &
    wait
}

case "${1:-}" in
    start)   start ;;
    stop)    stop ;;
    restart) stop; start ;;
    logs)    logs ;;
    *)
        echo "Usage: $0 <start|stop|restart|logs>"
        exit 1
        ;;
esac

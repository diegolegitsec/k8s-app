#!/usr/bin/env bash
# Usage:
#   ./scripts/deploy.sh vanilla   — build images locally, deploy to Docker Desktop K8s
#   ./scripts/deploy.sh aws       — deploy to EKS using GHCR images (reads config.env)
#   ./scripts/deploy.sh teardown  — delete all k8s-app resources from current context

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$ROOT/config.env"

# ── helpers ───────────────────────────────────────────────────────────────────

log() { echo "▶  $*"; }
err() { echo "✖  $*" >&2; exit 1; }

require_cmd() {
    command -v "$1" &>/dev/null || err "'$1' is required but not installed."
}

require_var() {
    [[ -n "${!1:-}" ]] || err "$1 is not set in config.env."
}

# Safely parse config.env without executing it as shell code.
load_config() {
    [[ -f "$CONFIG" ]] || err "config.env not found. Copy config.env.example → config.env and fill in your values."
    while IFS='=' read -r key val; do
        # Skip blank lines and comments
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
        # Only accept valid env var names (uppercase letters, digits, underscore)
        [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]] || continue
        # Strip inline comments, then surrounding whitespace
        val="${val%%#*}"
        val="${val#"${val%%[![:space:]]*}"}"
        val="${val%"${val##*[![:space:]]}"}"
        # Strip surrounding single or double quotes
        val="${val#\'}" ; val="${val%\'}"
        val="${val#\"}" ; val="${val%\"}"
        export "$key=$val"
    done < "$CONFIG"
}

# Substitute <OWNER>, <TAG>, <REDIS_PASSWORD>, and <ALLOWED_ORIGIN>
# in a manifest and pipe the result to kubectl apply.
apply_aws_manifest() {
    local file="$1"
    sed \
        -e "s|<OWNER>|${GITHUB_OWNER}|g" \
        -e "s|<TAG>|${IMAGE_TAG:-latest}|g" \
        -e "s|<REDIS_PASSWORD>|${REDIS_PASSWORD}|g" \
        -e "s|<ALLOWED_ORIGIN>|${ALLOWED_ORIGIN:-http://localhost}|g" \
        "$file" | kubectl apply -f -
}

# ── vanilla ───────────────────────────────────────────────────────────────────

deploy_vanilla() {
    require_cmd docker
    require_cmd kubectl

    log "Building backend image..."
    docker build -t k8s-app/backend:latest "$ROOT/backend"

    log "Building frontend image..."
    docker build -t k8s-app/frontend:latest "$ROOT/frontend"

    log "Applying manifests..."
    kubectl apply -f "$ROOT/k8s/local/namespace.yaml"
    kubectl apply -f "$ROOT/k8s/local/redis/pv.yaml"
    kubectl apply -f "$ROOT/k8s/local/redis/pvc.yaml"
    kubectl apply -f "$ROOT/k8s/local/redis/secret.yaml"
    kubectl apply -f "$ROOT/k8s/local/redis/deployment.yaml"
    kubectl apply -f "$ROOT/k8s/local/redis/service.yaml"
    kubectl apply -f "$ROOT/k8s/local/backend/configmap.yaml"
    kubectl apply -f "$ROOT/k8s/local/backend/deployment.yaml"
    kubectl apply -f "$ROOT/k8s/local/backend/service.yaml"
    kubectl apply -f "$ROOT/k8s/local/frontend/deployment.yaml"
    kubectl apply -f "$ROOT/k8s/local/frontend/service.yaml"
    kubectl apply -f "$ROOT/k8s/local/network-policies.yaml"

    log "Waiting for rollout..."
    kubectl rollout status deployment/redis    -n k8s-app
    kubectl rollout status deployment/backend  -n k8s-app
    kubectl rollout status deployment/frontend -n k8s-app

    echo ""
    echo "✔  App running at http://localhost"
    echo "   API:     http://localhost/api/entries"
}

# ── aws ───────────────────────────────────────────────────────────────────────

deploy_aws() {
    load_config
    require_cmd kubectl
    require_var GITHUB_OWNER
    require_var AWS_REGION
    require_var EKS_CLUSTER_NAME
    require_var REDIS_PASSWORD

    IMAGE_TAG="${IMAGE_TAG:-latest}"
    ALLOWED_ORIGIN="${ALLOWED_ORIGIN:-http://localhost}"

    log "Updating kubeconfig for EKS cluster '$EKS_CLUSTER_NAME' in $AWS_REGION..."
    aws eks update-kubeconfig --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION"

    log "Applying StorageClass and Namespace..."
    kubectl apply -f "$ROOT/k8s/aws/storageclass.yaml"
    kubectl apply -f "$ROOT/k8s/local/namespace.yaml"

    log "Applying NetworkPolicies..."
    kubectl apply -f "$ROOT/k8s/aws/network-policies.yaml"

    log "Applying Redis..."
    kubectl apply -f "$ROOT/k8s/aws/redis/pvc.yaml"
    apply_aws_manifest "$ROOT/k8s/aws/redis/secret.yaml"
    kubectl apply -f "$ROOT/k8s/aws/redis/deployment.yaml"
    kubectl apply -f "$ROOT/k8s/aws/redis/service.yaml"

    log "Applying backend..."
    apply_aws_manifest "$ROOT/k8s/aws/backend/configmap.yaml"
    apply_aws_manifest "$ROOT/k8s/aws/backend/deployment.yaml"
    kubectl apply -f "$ROOT/k8s/aws/backend/service.yaml"

    log "Applying frontend..."
    apply_aws_manifest "$ROOT/k8s/aws/frontend/deployment.yaml"
    kubectl apply -f "$ROOT/k8s/aws/frontend/service.yaml"

    log "Waiting for rollout..."
    kubectl rollout status deployment/redis    -n k8s-app
    kubectl rollout status deployment/backend  -n k8s-app
    kubectl rollout status deployment/frontend -n k8s-app

    NLB=$(kubectl get svc frontend-service -n k8s-app \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "<pending>")

    echo ""
    echo "✔  Deployment complete."
    echo "   Frontend: http://$NLB"
    if [[ "$NLB" == "<pending>" ]]; then
        echo "   (NLB may take 1-2 min to become active)"
    else
        echo ""
        echo "   Next: update ALLOWED_ORIGIN=http://$NLB in config.env and redeploy to lock down CORS."
    fi
}

# ── teardown ──────────────────────────────────────────────────────────────────

teardown() {
    log "Deleting namespace k8s-app and all resources inside it..."
    kubectl delete namespace k8s-app --ignore-not-found

    log "Deleting PersistentVolume redis-pv (if present)..."
    kubectl delete pv redis-pv --ignore-not-found

    log "Deleting StorageClass ebs-gp3 (if present)..."
    kubectl delete storageclass ebs-gp3 --ignore-not-found

    echo ""
    echo "✔  Teardown complete."
}

# ── entrypoint ────────────────────────────────────────────────────────────────

case "${1:-}" in
    vanilla)  deploy_vanilla ;;
    aws)      deploy_aws ;;
    teardown) teardown ;;
    *)
        echo "Usage: $0 <vanilla|aws|teardown>"
        echo ""
        echo "  vanilla   Build images locally and deploy to Docker Desktop K8s"
        echo "  aws       Deploy to EKS using GHCR images (requires config.env)"
        echo "  teardown  Remove all k8s-app resources from the current context"
        exit 1
        ;;
esac

#!/bin/bash
# deploy.sh — Deploy the full LGTM observability stack to Kubernetes
# Usage: bash scripts/deploy.sh
# Prerequisites: Run scripts/prerequisites.sh first

set -euo pipefail

# -----------------------------------------------------------------------
# Color helpers
# -----------------------------------------------------------------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }

NAMESPACE="observability"
TIMEOUT="8m"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

info "Deploying LGTM observability stack to namespace: ${NAMESPACE}"
info "Root directory: ${ROOT_DIR}"

# -----------------------------------------------------------------------
# Step 1: Create namespace and core config
# -----------------------------------------------------------------------
info "Step 1/7 — Applying namespace and ConfigMaps..."
kubectl apply -f "$ROOT_DIR/kubernetes/namespace.yaml"
kubectl apply -f "$ROOT_DIR/kubernetes/configmap.yaml"
info "  ✓ Namespace and ConfigMaps applied"

# -----------------------------------------------------------------------
# Step 2: Deploy Mimir (metrics backend — deploy first, others write to it)
# -----------------------------------------------------------------------
info "Step 2/7 — Deploying Mimir (metrics backend)..."
helm upgrade --install mimir grafana/mimir-distributed \
  --namespace "$NAMESPACE" \
  --values "$ROOT_DIR/helm/mimir/values.yaml" \
  --wait \
  --timeout "$TIMEOUT"
info "  ✓ Mimir deployed"

# -----------------------------------------------------------------------
# Step 3: Deploy Loki (log backend)
# -----------------------------------------------------------------------
info "Step 3/7 — Deploying Loki (log backend)..."
helm upgrade --install loki grafana/loki \
  --namespace "$NAMESPACE" \
  --values "$ROOT_DIR/helm/loki/values.yaml" \
  --wait \
  --timeout "$TIMEOUT"
info "  ✓ Loki deployed"

# -----------------------------------------------------------------------
# Step 4: Deploy Tempo (trace backend)
# -----------------------------------------------------------------------
info "Step 4/7 — Deploying Tempo (trace backend)..."
helm upgrade --install tempo grafana/tempo-distributed \
  --namespace "$NAMESPACE" \
  --values "$ROOT_DIR/helm/tempo/values.yaml" \
  --wait \
  --timeout "$TIMEOUT"
info "  ✓ Tempo deployed"

# -----------------------------------------------------------------------
# Step 5: Deploy Fluent Bit (log + metric collector)
# -----------------------------------------------------------------------
info "Step 5/7 — Deploying Fluent Bit (log collector DaemonSet)..."
helm upgrade --install fluent-bit fluent/fluent-bit \
  --namespace "$NAMESPACE" \
  --values "$ROOT_DIR/helm/fluent-bit/values.yaml" \
  --wait \
  --timeout 5m
info "  ✓ Fluent Bit deployed"

# -----------------------------------------------------------------------
# Step 6: Deploy Grafana (visualization + alerting)
# -----------------------------------------------------------------------
info "Step 6/7 — Deploying Grafana (visualization)..."
helm upgrade --install grafana grafana/grafana \
  --namespace "$NAMESPACE" \
  --values "$ROOT_DIR/helm/grafana/values.yaml" \
  --wait \
  --timeout 5m
info "  ✓ Grafana deployed"

# -----------------------------------------------------------------------
# Step 7: Verify all pods
# -----------------------------------------------------------------------
info "Step 7/7 — Verifying pod status..."
echo ""
kubectl get pods -n "$NAMESPACE"
echo ""

# Check for any non-Running pods
NOT_RUNNING=$(kubectl get pods -n "$NAMESPACE" --no-headers | grep -v "Running\|Completed" | wc -l | tr -d ' ')
if [[ "$NOT_RUNNING" -gt 0 ]]; then
  warn "${NOT_RUNNING} pod(s) not yet Running. Check 'kubectl describe pod <name> -n ${NAMESPACE}' for details."
else
  info "  ✓ All pods Running"
fi

# -----------------------------------------------------------------------
# Print access instructions
# -----------------------------------------------------------------------
echo ""
info "============================================================"
info "Stack deployed successfully!"
info "============================================================"
echo ""
info "Get Grafana admin password:"
echo "  kubectl get secret --namespace ${NAMESPACE} grafana -o jsonpath='{.data.admin-password}' | base64 --decode && echo"
echo ""
info "Port-forward Grafana to localhost:3000:"
echo "  kubectl port-forward --namespace ${NAMESPACE} svc/grafana 3000:80"
echo "  Open: http://localhost:3000"
echo ""
info "Port-forward Loki (direct testing):"
echo "  kubectl port-forward --namespace ${NAMESPACE} svc/loki-gateway 3100:80"
echo ""
info "Port-forward Mimir (direct testing):"
echo "  kubectl port-forward --namespace ${NAMESPACE} svc/mimir-nginx 9009:80"
echo ""
info "Port-forward Tempo OTLP gRPC (send traces from local app):"
echo "  kubectl port-forward --namespace ${NAMESPACE} svc/tempo-distributor 4317:4317"

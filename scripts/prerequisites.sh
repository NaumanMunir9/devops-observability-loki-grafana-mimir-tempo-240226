#!/bin/bash
# prerequisites.sh — Check and install all requirements for the observability stack
# Usage: bash scripts/prerequisites.sh

set -euo pipefail

# -----------------------------------------------------------------------
# Color helpers
# -----------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# -----------------------------------------------------------------------
# Check required tools
# -----------------------------------------------------------------------
info "Checking required tools..."

check_tool() {
  local tool=$1
  local install_hint=$2
  if ! command -v "$tool" &>/dev/null; then
    error "'$tool' is not installed. $install_hint"
  fi
  info "  ✓ $tool found: $(command -v $tool)"
}

check_tool kubectl   "Install: https://kubernetes.io/docs/tasks/tools/"
check_tool helm      "Install: https://helm.sh/docs/intro/install/"

# -----------------------------------------------------------------------
# Check kubectl context
# -----------------------------------------------------------------------
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "none")
info "Current kubectl context: ${CURRENT_CONTEXT}"

if [[ "$CURRENT_CONTEXT" == "none" ]]; then
  error "No kubectl context is set. Configure your kubeconfig before proceeding."
fi

# Confirm the user wants to deploy to this cluster
echo ""
warn "You are about to deploy to cluster context: ${CURRENT_CONTEXT}"
read -r -p "Continue? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }

# -----------------------------------------------------------------------
# Check cluster connectivity
# -----------------------------------------------------------------------
info "Testing cluster connectivity..."
kubectl get nodes --no-headers > /dev/null || error "Cannot connect to cluster. Check your kubeconfig."
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
info "  ✓ Cluster reachable — ${NODE_COUNT} node(s) found"

# -----------------------------------------------------------------------
# Check available cluster resources (basic estimate)
# -----------------------------------------------------------------------
info "Checking cluster resource capacity..."
kubectl top nodes 2>/dev/null || warn "kubectl top nodes not available — metrics-server may not be installed"

# -----------------------------------------------------------------------
# Check StorageClass
# -----------------------------------------------------------------------
info "Checking StorageClass availability..."
SC_COUNT=$(kubectl get storageclass --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "$SC_COUNT" -eq 0 ]]; then
  warn "No StorageClass found. PersistentVolumeClaims may fail. Ensure a StorageClass is configured."
else
  DEFAULT_SC=$(kubectl get storageclass --no-headers | grep '(default)' | awk '{print $1}' || echo "none")
  info "  ✓ ${SC_COUNT} StorageClass(es) found. Default: ${DEFAULT_SC}"
fi

# -----------------------------------------------------------------------
# Add and update Helm repositories
# -----------------------------------------------------------------------
info "Adding Helm repositories..."

helm repo add grafana   https://grafana.github.io/helm-charts    || warn "grafana repo already exists"
helm repo add fluent    https://fluent.github.io/helm-charts      || warn "fluent repo already exists"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || warn "prometheus-community repo already exists"

info "Updating Helm repositories..."
helm repo update

# -----------------------------------------------------------------------
# Verify charts are available
# -----------------------------------------------------------------------
info "Verifying chart availability..."

check_chart() {
  local repo_chart=$1
  helm search repo "$repo_chart" --output table 2>/dev/null | grep -q "$repo_chart" \
    && info "  ✓ $repo_chart" \
    || warn "  ✗ $repo_chart not found — check repo name"
}

check_chart "grafana/loki"
check_chart "grafana/mimir-distributed"
check_chart "grafana/tempo-distributed"
check_chart "grafana/grafana"
check_chart "fluent/fluent-bit"

# -----------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------
echo ""
info "Prerequisites check complete. Run 'bash scripts/deploy.sh' to deploy the stack."

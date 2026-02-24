#!/bin/bash
# teardown.sh — Remove the full LGTM observability stack from Kubernetes
# Usage: bash scripts/teardown.sh
# WARNING: This will delete all data stored in Loki, Mimir, and Tempo

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

NAMESPACE="observability"

warn "============================================================"
warn "WARNING: This will DELETE all observability data!"
warn "All logs (Loki), metrics (Mimir), and traces (Tempo) will"
warn "be permanently lost if PVCs are deleted."
warn "============================================================"
echo ""
read -r -p "Type 'yes' to confirm teardown: " confirm
[[ "$confirm" == "yes" ]] || { info "Aborted."; exit 0; }

# -----------------------------------------------------------------------
# Remove Helm releases in reverse deployment order
# -----------------------------------------------------------------------
for release in grafana fluent-bit tempo loki mimir; do
  if helm status "$release" --namespace "$NAMESPACE" &>/dev/null; then
    info "Removing Helm release: $release..."
    helm uninstall "$release" --namespace "$NAMESPACE" --wait || warn "Failed to remove $release — may already be removed"
  else
    info "  Skipping $release — not installed"
  fi
done

# -----------------------------------------------------------------------
# Remove Kubernetes resources
# -----------------------------------------------------------------------
info "Removing ConfigMaps..."
kubectl delete -f kubernetes/configmap.yaml --ignore-not-found
kubectl delete -f kubernetes/namespace.yaml --ignore-not-found

# -----------------------------------------------------------------------
# Optional: remove PVCs (data permanently deleted)
# -----------------------------------------------------------------------
echo ""
warn "Do you also want to delete all PersistentVolumeClaims? (ALL DATA WILL BE LOST)"
read -r -p "Delete PVCs? [y/N] " delete_pvcs
if [[ "$delete_pvcs" =~ ^[Yy]$ ]]; then
  kubectl delete pvc --all -n "$NAMESPACE" || warn "No PVCs found or already deleted"
  info "  ✓ PVCs deleted"
  kubectl delete namespace "$NAMESPACE" --ignore-not-found
  info "  ✓ Namespace deleted"
else
  info "PVCs preserved. Namespace ${NAMESPACE} still exists."
fi

info "Teardown complete."

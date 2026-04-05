#!/bin/bash
set -euo pipefail
#
# check-environment.sh — Health check for Azure eval environment
#
# Verifies that the Bicep deployment succeeded and key resources exist.
# Called after before_run hook; if this fails, the run is skipped.
#

source "$(dirname "${BASH_SOURCE[0]}")/azure-auth.sh"

RG="${EVAL_RESOURCE_GROUP:?EVAL_RESOURCE_GROUP not set}"

echo "[health] Checking environment in $RG..."

# Check resource group exists
az group show --name "$RG" --output none 2>/dev/null || {
  echo "[health] ✗ Resource group $RG not found"
  exit 1
}

# Check minimum resource count (Bicep deploys ~10 resources)
COUNT=$(az resource list --resource-group "$RG" --query 'length(@)' -o tsv 2>/dev/null || echo "0")
if [[ "$COUNT" -lt 8 ]]; then
  echo "[health] ✗ Only $COUNT resources in $RG (expected ≥8)"
  exit 1
fi

# Check App Service exists and is running
APP_NAME=$(az webapp list -g "$RG" --query '[0].name' -o tsv 2>/dev/null || echo "")
if [[ -z "$APP_NAME" ]]; then
  echo "[health] ✗ No App Service found in $RG"
  exit 1
fi

echo "[health] ✓ Environment ready ($COUNT resources, app: $APP_NAME)"

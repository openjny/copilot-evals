#!/bin/bash
set -euo pipefail
# Inject an error into the App Service to create something for diagnostics to find.
# Sets an invalid app setting that causes startup warnings.

RG="${EVAL_RESOURCE_GROUP:?EVAL_RESOURCE_GROUP not set}"
APP=$(az webapp list -g "$RG" --query '[0].name' -o tsv 2>/dev/null)

if [[ -z "$APP" ]]; then
  echo "[hook] No App Service found in $RG, skipping error injection"
  exit 0
fi

echo "[hook] Injecting error into $APP..."
az webapp config appsettings set -g "$RG" -n "$APP" \
  --settings BROKEN_SETTING=intentional_error WEBSITE_NODE_DEFAULT_VERSION=0.0.0 \
  --output none 2>/dev/null || true
echo "[hook] Error injected"

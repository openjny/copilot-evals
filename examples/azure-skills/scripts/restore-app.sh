#!/bin/bash
set -euo pipefail
# Restore the App Service after diagnostics eval.
# Removes the injected error settings.

RG="${EVAL_RESOURCE_GROUP:?EVAL_RESOURCE_GROUP not set}"
APP=$(az webapp list -g "$RG" --query '[0].name' -o tsv 2>/dev/null)

if [[ -z "$APP" ]]; then
  echo "[hook] No App Service found in $RG, skipping restore"
  exit 0
fi

echo "[hook] Restoring $APP..."
az webapp config appsettings delete -g "$RG" -n "$APP" \
  --setting-names BROKEN_SETTING WEBSITE_NODE_DEFAULT_VERSION \
  --output none 2>/dev/null || true
echo "[hook] Restored"

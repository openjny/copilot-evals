#!/bin/bash
set -euo pipefail
#
# verify-compliance-audit.sh — compliance-audit task evaluator
#
# Verifies that the Copilot output correctly identified key security/compliance
# properties of the deployed resources. Checks the actual Azure configuration
# and compares against what a correct compliance audit should find.
#

RG="${EVAL_RESOURCE_GROUP:?EVAL_RESOURCE_GROUP not set}"

source "$(dirname "${BASH_SOURCE[0]}")/azure-auth.sh"

echo "[verify] Running compliance checks on $RG..."

PASS=0
FAIL=0

check() {
  local label="$1" actual="$2" expected="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "  ✓ $label = $actual"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label = $actual (expected: $expected)"
    FAIL=$((FAIL + 1))
  fi
}

# --- App Service: HTTPS-only, FTPS disabled, TLS 1.2 ---
APP_NAME=$(az webapp list -g "$RG" --query '[0].name' -o tsv 2>/dev/null || echo "")
if [[ -n "$APP_NAME" ]]; then
  echo "[verify] App Service: $APP_NAME"
  HTTPS_ONLY=$(az webapp show -g "$RG" -n "$APP_NAME" --query 'httpsOnly' -o tsv 2>/dev/null)
  FTPS_STATE=$(az webapp config show -g "$RG" -n "$APP_NAME" --query 'ftpsState' -o tsv 2>/dev/null)
  MIN_TLS=$(az webapp config show -g "$RG" -n "$APP_NAME" --query 'minTlsVersion' -o tsv 2>/dev/null)
  check "httpsOnly" "$HTTPS_ONLY" "true"
  check "ftpsState" "$FTPS_STATE" "Disabled"
  check "minTlsVersion" "$MIN_TLS" "1.2"
else
  echo "[verify] WARNING: No App Service found"
  FAIL=$((FAIL + 1))
fi

# --- Storage Account: HTTPS-only, no public blob access, public network disabled ---
STORAGE_NAME=$(az storage account list -g "$RG" --query '[0].name' -o tsv 2>/dev/null || echo "")
if [[ -n "$STORAGE_NAME" ]]; then
  echo "[verify] Storage Account: $STORAGE_NAME"
  HTTPS_TRAFFIC=$(az storage account show -g "$RG" -n "$STORAGE_NAME" --query 'enableHttpsTrafficOnly' -o tsv 2>/dev/null)
  BLOB_PUBLIC=$(az storage account show -g "$RG" -n "$STORAGE_NAME" --query 'allowBlobPublicAccess' -o tsv 2>/dev/null)
  PUBLIC_NET=$(az storage account show -g "$RG" -n "$STORAGE_NAME" --query 'publicNetworkAccess' -o tsv 2>/dev/null)
  MIN_TLS_STORAGE=$(az storage account show -g "$RG" -n "$STORAGE_NAME" --query 'minimumTlsVersion' -o tsv 2>/dev/null)
  check "supportsHttpsTrafficOnly" "$HTTPS_TRAFFIC" "true"
  check "allowBlobPublicAccess" "$BLOB_PUBLIC" "false"
  check "publicNetworkAccess" "$PUBLIC_NET" "Disabled"
  check "minimumTlsVersion" "$MIN_TLS_STORAGE" "TLS1_2"
else
  echo "[verify] WARNING: No Storage Account found"
  FAIL=$((FAIL + 1))
fi

# --- SQL Server: Entra-only auth, public network disabled, TLS 1.2 ---
SQL_NAME=$(az sql server list -g "$RG" --query '[0].name' -o tsv 2>/dev/null || echo "")
if [[ -n "$SQL_NAME" ]]; then
  echo "[verify] SQL Server: $SQL_NAME"
  AAD_ONLY=$(az sql server show -g "$RG" -n "$SQL_NAME" --query 'administrators.azureAdOnlyAuthentication' -o tsv 2>/dev/null)
  SQL_PUBLIC=$(az sql server show -g "$RG" -n "$SQL_NAME" --query 'publicNetworkAccess' -o tsv 2>/dev/null)
  SQL_TLS=$(az sql server show -g "$RG" -n "$SQL_NAME" --query 'minimalTlsVersion' -o tsv 2>/dev/null)
  check "azureAdOnlyAuthentication" "$AAD_ONLY" "true"
  check "publicNetworkAccess" "$SQL_PUBLIC" "Disabled"
  check "minimalTlsVersion" "$SQL_TLS" "1.2"
else
  echo "[verify] WARNING: No SQL Server found"
  FAIL=$((FAIL + 1))
fi

# --- Private Endpoints exist ---
PE_COUNT=$(az network private-endpoint list -g "$RG" --query 'length(@)' -o tsv 2>/dev/null || echo "0")
echo "[verify] Private Endpoints: $PE_COUNT"
if [[ "$PE_COUNT" -ge 2 ]]; then
  echo "  ✓ At least 2 private endpoints found"
  PASS=$((PASS + 1))
else
  echo "  ✗ Expected at least 2 private endpoints, found $PE_COUNT"
  FAIL=$((FAIL + 1))
fi

# --- Summary ---
TOTAL=$((PASS + FAIL))
echo ""
echo "[verify] Compliance check: $PASS/$TOTAL passed"

if [[ "$FAIL" -eq 0 ]]; then
  echo "[verify] ✓ All compliance checks passed"
  exit 0
else
  echo "[verify] ✗ $FAIL compliance check(s) failed"
  exit 1
fi

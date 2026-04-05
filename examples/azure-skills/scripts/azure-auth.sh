#!/bin/bash
# azure-auth.sh — Authenticate with SP credentials from .env
# Source this at the start of any script that needs Azure CLI access.
#
# Expects AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID in environment
# (loaded from .env by the runner).

if [[ -n "${AZURE_CLIENT_ID:-}" && -n "${AZURE_CLIENT_SECRET:-}" && -n "${AZURE_TENANT_ID:-}" ]]; then
  az login --service-principal \
    -u "$AZURE_CLIENT_ID" -p "$AZURE_CLIENT_SECRET" --tenant "$AZURE_TENANT_ID" \
    --output none 2>/dev/null
  if [[ -n "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
    az account set --subscription "$AZURE_SUBSCRIPTION_ID" --output none 2>/dev/null
  fi
fi

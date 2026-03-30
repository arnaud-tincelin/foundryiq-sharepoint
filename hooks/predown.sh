#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Pre-down hook – cleans up Entra ID resources that are NOT removed when
# the Azure resource group is deleted.
#
# Deletes:
#   1. The Entra app registration created by sharepoint-app.bicep
#      (the associated service principal is deleted automatically).
#   2. The federated identity credential (child of the app, deleted with it).
#
# The SHAREPOINT_APP_ID environment variable is set automatically by Bicep
# outputs during provisioning.
# ---------------------------------------------------------------------------
set -euo pipefail

echo "==> Cleaning up Entra ID resources before tearing down infrastructure…"

APP_ID="${SHAREPOINT_APP_ID:-}"

if [[ -z "$APP_ID" ]]; then
  echo "  ⚠️  SHAREPOINT_APP_ID is not set - nothing to clean up."
  exit 0
fi

# Check if the app registration still exists
if az ad app show --id "$APP_ID" &>/dev/null; then
  # Get the object ID needed for permanent deletion
  OBJECT_ID=$(az ad app show --id "$APP_ID" --query id -o tsv)
  echo "  🗑️  Deleting Entra app registration (appId: $APP_ID)…"
  az ad app delete --id "$APP_ID"
  echo "  ✅ App registration soft-deleted."

  # Permanently purge so the uniqueName is freed for re-provisioning
  echo "  🗑️  Permanently purging soft-deleted app…"
  if az rest --method DELETE --url "https://graph.microsoft.com/v1.0/directory/deletedItems/${OBJECT_ID}" 2>/dev/null; then
    echo "  ✅ App permanently purged."
  else
    echo "  ⚠️  Purge failed — may need to wait or delete manually in Entra portal."
  fi
else
  echo "  ℹ️  App registration (appId: $APP_ID) not found - already deleted or never created."
fi

echo "==> Entra ID cleanup complete."

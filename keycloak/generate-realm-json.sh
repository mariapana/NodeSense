#!/bin/bash

set -e

# ==============================================================================
#    NODE MONITORING PLATFORM – REALM JSON GENERATOR
# ==============================================================================
echo "=============================================================================="
echo "███╗   ██╗ ██████╗ ██████╗ ███████╗███████╗███████╗███╗   ██╗███████╗███████╗"
echo "████╗  ██║██╔═══██╗██╔══██╗██╔════╝██╔════╝██╔════╝████╗  ██║██╔════╝██╔════╝"
echo "██╔██╗ ██║██║   ██║██║  ██║█████╗  ███████╗█████╗  ██╔██╗ ██║███████╗█████╗"
echo "██║╚██╗██║██║   ██║██║  ██║██╔══╝  ╚════██║██╔══╝  ██║╚██╗██║╚════██║██╔══╝"
echo "██║ ╚████║╚██████╔╝██████╔╝███████╗███████║███████╗██║ ╚████║███████║███████╗"
echo "╚═╝  ╚═══╝ ╚═════╝ ╚═════╝ ╚══════╝╚══════╝╚══════╝╚═╝  ╚═══╝╚══════╝╚══════╝"
echo "=============================================================================="
echo ""

# ==============================================================================

if [ "$#" -ne 3 ]; then
    echo "[ERROR] Usage: $0 <admin_password> <viewer_password> <client_secret>"
    exit 1
fi

ADMIN_PASS="$1"
VIEWER_PASS="$2"
CLIENT_SECRET="$3"

TEMPLATE="keycloak/import/NodeSense-realm.template.json"
OUTPUT="keycloak/import/NodeSense-realm.json"

if [ ! -f "$TEMPLATE" ]; then
    echo "[ERROR] Template not found: $TEMPLATE"
    exit 1
fi

echo "[INFO] Generating private realm JSON..."

cat "$TEMPLATE" \
    | sed "s|__ADMIN_PASSWORD__|$ADMIN_PASS|g" \
    | sed "s|__VIEWER_PASSWORD__|$VIEWER_PASS|g" \
    | sed "s|__CLIENT_SECRET__|$CLIENT_SECRET|g" \
    > "$OUTPUT"

echo "[OK] Generated private realm JSON at: $OUTPUT"
echo ""
echo "IMPORTANT: Do NOT commit this file to GitHub."

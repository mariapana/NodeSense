#!/bin/bash

# Configuration
KEYCLOAK_URL=${KEYCLOAK_URL:-"http://localhost:8080"}
REALM=${REALM:-"NodeSense"}
CLIENT_ID=${CLIENT_ID:-"api-gateway"}
# NOTE: In a real app, you'd use a confidential client or Authorization Code flow.
# For this CLI demo, we'll assume Direct Access Grants (Resource Owner Password Credentials) 
# is enabled for the client or we use the admin-cli if permitted.
# However, usually 'gateway-client' is confidential or public.
# Let's try to get a token using the 'admin-cli' or a dedicated user if we know the credentials.
# Given the setup script, we have an admin user and a 'viewer' user (if created via UI/script).
# Let's assume the user uses the ADMIN credentials they set up, or we can prompt.

# We will try to use the 'gateway-client' if it has Direct Access enabled, 
# otherwise we might fail if it's only for backend/service-accounts.
# Actually, usually getting a user token is best done via 'admin-cli' for testing 
# or a specific public client 'nodesense-frontend'. 
# Let's assume 'nodesense-frontend' or similar exists or just use 'gateway-client' if it allows it.
# Check stack.yml/auth.py for clues. 
# Creating a dedicated public client for testing is safer.
# For now, let's use the standard token endpoint.

echo "--- Get Keycloak Token ---"
read -p "Username: " USERNAME
read -s -p "Password: " PASSWORD
echo ""

# Try to get token for the 'admin-cli' which usually exists, 
# or 'gateway-client' if it's set to public/direct-access.
# We'll default to 'gateway-client' as that's what the gateway expects audience for (maybe).
# But wait, auth.py checks signature. It doesn't strictly check audience unless configured.
# Let's try 'gateway-client' first. If it needs a secret, we'd need to provide it.
# If it's a confidential client (default for backend), we need client_secret.

read -s -p "Client Secret (leave empty if public client): " CLIENT_SECRET
echo ""

DATA="grant_type=password&username=${USERNAME}&password=${PASSWORD}&client_id=${CLIENT_ID}"
if [ -n "$CLIENT_SECRET" ]; then
    DATA="${DATA}&client_secret=${CLIENT_SECRET}"
fi

echo "Sending request to Keycloak ($KEYCLOAK_URL)..."
# Use -f to fail on HTTP errors, -S to show errors
RESPONSE=$(curl -s -S -f --max-time 10 -X POST "${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "$DATA" 2>&1)
CURL_EXIT_CODE=$?

if [ $CURL_EXIT_CODE -ne 0 ]; then
    echo "Error: Failed to connect to Keycloak from host (Exit Code: $CURL_EXIT_CODE)."
    echo "Attempting fallback via internal Docker network..."
    
    # Find a container to run the request from (using alerting service which has python+requests)
    CONTAINER_ID=$(docker ps -q -f name=monitor-platform_alerting | head -n 1)
    
    if [ -n "$CONTAINER_ID" ]; then
        echo "Using container $CONTAINER_ID to fetch token..."
        
        # Prepare Python script
        PY_SCRIPT="
import requests
import sys
try:
    url = 'http://keycloak:8080/realms/${REALM}/protocol/openid-connect/token'
    data = {
        'grant_type': 'password',
        'username': '${USERNAME}',
        'password': '${PASSWORD}',
        'client_id': '${CLIENT_ID}',
        'client_secret': '${CLIENT_SECRET}'
    }
    resp = requests.post(url, data=data, timeout=10)
    print(resp.text)
except Exception as e:
    print(str(e))
    sys.exit(1)
"
        RESPONSE=$(docker exec "$CONTAINER_ID" python -c "$PY_SCRIPT")
    else
        echo "Error: No suitable container found for fallback."
        exit 1
    fi
fi

if echo "$RESPONSE" | grep -q "access_token"; then
    TOKEN=$(echo "$RESPONSE" | grep -o '"access_token":"[^"]*' | grep -o '[^"]*$')
    echo ""
    echo "Access Token retrieved successfully!"
    echo "-------------------------------------"
    echo "$TOKEN"
    echo "-------------------------------------"
    echo "Usage:"
    echo "curl -H \"Authorization: Bearer \$TOKEN\" http://localhost:8000/ingest"
else
    echo ""
    echo "Failed to retrieve token."
    echo "Full Response:"
    echo "$RESPONSE"
fi

#!/bin/bash

# Configuration
GATEWAY_URL="http://gateway:8000"
CONTAINER_ID=$(docker ps -q -f name=monitor-platform_alerting | head -n 1)

if [ -z "$CONTAINER_ID" ]; then
    echo "Error: Alerting service container not found. Is the stack running?"
    exit 1
fi

echo "--- Sending Test Metric via Internal Network ---"
echo "Container: $CONTAINER_ID"

# Check if token is provided as argument
TOKEN="$1"
if [ -z "$TOKEN" ]; then
    echo ""
    echo "Usage: ./test_ingest.sh <ACCESS_TOKEN>"
    echo "Please provide the token you retrieved from ./get_token.sh"
    exit 1
fi

# Prepare Python script to run inside container
# We use python because curl might not be installed in the alerting image
PY_SCRIPT="
import requests
import json
import time

url = '${GATEWAY_URL}/ingest'
headers = {
    'Authorization': 'Bearer ${TOKEN}',
    'Content-Type': 'application/json'
}
data = {
    'node_id': 'test-node-workaround',
    'timestamp': '2026-01-10T16:00:00Z',
    'metrics': [
        {'name': 'cpu_usage', 'value': 42.0},
        {'name': 'memory_usage', 'value': 128.0}
    ]
}

print(f'Sending POST to {url}...')
try:
    resp = requests.post(url, headers=headers, json=data, timeout=10)
    print(f'Status: {resp.status_code}')
    print(f'Response: {resp.text}')
except Exception as e:
    print(f'Error: {e}')
"

docker exec "$CONTAINER_ID" python -c "$PY_SCRIPT"

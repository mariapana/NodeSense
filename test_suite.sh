#!/bin/bash

# ================= BANNER =================
echo "=============================================================================="
echo "███╗   ██╗ ██████╗ ██████╗ ███████╗███████╗███████╗███╗   ██╗███████╗███████╗"
echo "████╗  ██║██╔═══██╗██╔══██╗██╔════╝██╔════╝██╔════╝████╗  ██║██╔════╝██╔════╝"
echo "██╔██╗ ██║██║   ██║██║  ██║█████╗  ███████╗█████╗  ██╔██╗ ██║███████╗█████╗"
echo "██║╚██╗██║██║   ██║██║  ██║██╔══╝  ╚════██║██╔══╝  ██║╚██╗██║╚════██║██╔══╝"
echo "██║ ╚████║╚██████╔╝██████╔╝███████╗███████║███████╗██║ ╚████║███████║███████╗"
echo "╚═╝  ╚═══╝ ╚═════╝ ╚═════╝ ╚══════╝╚══════╝╚══════╝╚═╝  ╚═══╝╚══════╝╚══════╝"
echo "============================================================================="
echo "                           N O D E   M O N I T O R I N G   P L A T F O R M"
echo ""

# Configuration
KEYCLOAK_URL=${KEYCLOAK_URL:-"http://keycloak:8080"}
GATEWAY_URL=${GATEWAY_URL:-"http://gateway:8000"}
REALM=${REALM:-"NodeSense"}
CLIENT_ID="api-gateway"
GRAFANA_URL="http://127.0.0.1:3001"
KEYCLOAK_ADMIN_URL="http://127.0.0.1:8080"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
log_cmd() { echo -e "${YELLOW}[CMD]${NC} $1"; }

section() { 
    echo ""
    echo -e "${YELLOW}==========================================================${NC}"
    echo -e "${YELLOW}      $1${NC}"
    echo -e "${YELLOW}==========================================================${NC}"
}

# Credentials
USERNAME=${1:-"admin"}
PASSWORD=${2:-"admin"}

section "NodeSense Comprehensive Verification"

log_info "Detecting suitable runner container (internal network access)..."
CONTAINER_ID=$(docker ps -q -f name=monitor-platform_alerting | head -n 1)
DB_CONTAINER=$(docker ps -q -f name=monitor-platform_timescaledb | head -n 1)

if [ -z "$CONTAINER_ID" ]; then
    log_fail "Alerting service container not found. Is the stack running?"
    log_info "Try running ./deploy.sh first."
    exit 1
fi
log_info "Using container $CONTAINER_ID"

# Ask for client secret if not set
if [ -z "$3" ]; then
    echo "Please enter the Client Secret for 'api-gateway' (from deploy output or Keycloak console)."
    read -s -p "Client Secret: " CLIENT_SECRET
    echo ""
else
    CLIENT_SECRET="$3"
fi

# ================= AUTOMATED TESTS =================

section "PHASE 1: Authentication Check"
log_info "Attempting to retrieve JWT Token from Keycloak..."

PY_GET_TOKEN="
import requests
import sys
try:
    url = '${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token'
    data = {
        'grant_type': 'password',
        'username': '${USERNAME}',
        'password': '${PASSWORD}',
        'client_id': '${CLIENT_ID}',
        'client_secret': '${CLIENT_SECRET}'
    }
    resp = requests.post(url, data=data, timeout=10)
    if resp.status_code == 200:
        print(resp.json()['access_token'])
    else:
        print(f'ERROR: {resp.status_code} {resp.text}', file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print(str(e), file=sys.stderr)
    sys.exit(1)
"

TOKEN=$(docker exec "$CONTAINER_ID" python -c "$PY_GET_TOKEN")
if [ $? -ne 0 ]; then
    log_fail "Could not retrieve token."
    echo "$TOKEN"
    exit 1
fi
log_pass "Token retrieved successfully."

# ---------------------------------------------------------

section "PHASE 2: Security Enforcement"
log_info "Description: Verify that unauthenticated requests to the Gateway are blocked."
log_info "Testing Unauthenticated Access (Expect 401/403)..."
log_cmd "docker exec $CONTAINER_ID python -c \"...requests.post(url, json={}, timeout=5)...\""

PY_AUTH_FAIL="
import requests
import sys
url = '${GATEWAY_URL}/ingest'
try:
    # Use POST to avoid 405 Method Not Allowed masking the check
    resp = requests.post(url, json={}, timeout=5) 
    if resp.status_code == 401 or resp.status_code == 403:
        print('SUCCESS')
    else:
        print(f'FAIL: Expected 401/403, got {resp.status_code}')
        sys.exit(1)
except Exception as e:
    print(str(e))
    sys.exit(1)
"
docker exec "$CONTAINER_ID" python -c "$PY_AUTH_FAIL" && log_pass "Request blocked as expected." || log_fail "Security check failed! Gateway might not be enforcing Auth."

# ---------------------------------------------------------

section "PHASE 3: Full Metric Ingestion (Spec Compliance)"
log_info "Description: Verify that the Gateway accepts a payload with all spec-defined metrics."
log_info "Sending payload with ALL spec-defined metrics (cpu, mem, disk, process_count)..."
log_cmd "docker exec $CONTAINER_ID python -c \"...requests.post(url, json=data)...\""

PY_FULL_INGEST="
import requests
import sys
url = '${GATEWAY_URL}/ingest'
headers = {'Authorization': 'Bearer ${TOKEN}', 'Content-Type': 'application/json'}
data = {
    'node_id': 'spec-test-node',
    'timestamp': '2026-01-10T17:00:00Z',
    'metrics': [
        {'name': 'cpu_usage', 'value': 25.0, 'unit': '%'},
        {'name': 'mem_used', 'value': 1024000, 'unit': 'bytes'},
        {'name': 'process_count', 'value': 150, 'unit': 'count'},
        {'name': 'disk_percent', 'value': 45.0, 'unit': '%'},
        {'name': 'load_avg_1m', 'value': 0.5, 'unit': '%'}
    ]
}
try:
    resp = requests.post(url, headers=headers, json=data, timeout=5)
    if resp.status_code == 200:
        print('SUCCESS')
    else:
        print(f'FAIL: {resp.status_code} {resp.text}')
        sys.exit(1)
except Exception as e:
    print(str(e))
    sys.exit(1)
"
docker exec "$CONTAINER_ID" python -c "$PY_FULL_INGEST" && log_pass "Full metric payload accepted." || log_fail "Ingest failed."

# ---------------------------------------------------------

section "PHASE 4: Alerting Service - High CPU"
log_info "Description: Verify that sending a high CPU metric triggers an alert log."
log_info "Triggering High CPU Alert (>90%)..."
log_cmd "docker exec $CONTAINER_ID python -c \"...requests.post(...value: 99.9...)\""

PY_ALERT="
import requests
import sys
import datetime
url = '${GATEWAY_URL}/ingest'
headers = {'Authorization': 'Bearer ${TOKEN}', 'Content-Type': 'application/json'}
data = {
    'node_id': 'alert-cpu-node',
    'timestamp': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'metrics': [{'name': 'cpu_usage', 'value': 99.9}]
}
try:
    requests.post(url, headers=headers, json=data, timeout=5)
    print('SENT')
except Exception as e:
    print(str(e))
"
docker exec "$CONTAINER_ID" python -c "$PY_ALERT"
log_info "Metric sent. Waiting 30s for alert check (Interval=10s)..."
sleep 30
# Check DB for alert
docker exec $DB_CONTAINER psql -U nodesense -d nodesense -c "SELECT * FROM alerts WHERE message LIKE '%High CPU%';" > /tmp/alert_check.txt
if grep -q "High CPU" /tmp/alert_check.txt; then
    log_pass "Alert triggered found in DB:"
    # Only show the relevant lines to avoid flooding
    grep "High CPU" /tmp/alert_check.txt | tail -n 5
else
    log_fail "Alert not found in DB."
    log_info "Checking logs as backup..."
    docker service logs --tail 20 monitor-platform_alerting
fi

# ---------------------------------------------------------

section "PHASE 5: Alerting Service - Node Down"
log_info "Description: Verify that a node not seen for > 2 minutes triggers a Node Down alert."
log_info "Simulating Dead Node (No report for > 2 mins)..."
log_cmd "docker exec $DB_CONTAINER psql ... INSERT dead-node-1 with old timestamp"
# Upsert: If exists, update last_seen to old time. If new, insert with old time.
docker exec $DB_CONTAINER psql -U nodesense -d nodesense -c "INSERT INTO nodes (id, name, last_seen) VALUES ('dead-node-1', 'dead-node-1', NOW() - INTERVAL '5 minutes') ON CONFLICT (id) DO UPDATE SET last_seen = EXCLUDED.last_seen;" > /dev/null
# Verify insertion
log_cmd "docker exec $DB_CONTAINER psql ... SELECT id, last_seen FROM nodes WHERE id='dead-node-1'"
docker exec $DB_CONTAINER psql -U nodesense -d nodesense -c "SELECT id, last_seen FROM nodes WHERE id='dead-node-1';"

log_info "Waiting 15s for alert check..."
sleep 15
# Check DB
docker exec $DB_CONTAINER psql -U nodesense -d nodesense -c "SELECT * FROM alerts WHERE message LIKE '%Node Down%';" > /tmp/node_down_check.txt
if grep -q "dead-node-1" /tmp/node_down_check.txt; then
    log_pass "Node Down alert found in DB for 'dead-node-1':"
    grep "dead-node-1" /tmp/node_down_check.txt | head -n 1
else
    log_fail "Node Down alert for 'dead-node-1' NOT found in DB."
    log_info "Recent alerts (tail 5):"
    docker exec $DB_CONTAINER psql -U nodesense -d nodesense -c "SELECT * FROM alerts ORDER BY timestamp DESC LIMIT 5;"
fi

# ---------------------------------------------------------

section "PHASE 6: Rate Limiting"
log_info "Description: Verify that sending >100 requests/min to the Gateway triggers a 429 response."
log_info "Testing Rate Limit (Max 100/min)..."
log_info "Sending 150 requests rapidly..."
log_cmd "docker exec $CONTAINER_ID python -c \"...loop sending requests...\""

PY_RATELIMIT="
import requests
import sys
url = '${GATEWAY_URL}/ingest'
headers = {'Authorization': 'Bearer ${TOKEN}', 'Content-Type': 'application/json'}
data = {'node_id': 'spam-node', 'timestamp': '2026-01-10T17:00:00Z', 'metrics': [{'name': 'cpu', 'value': 1}]}
limited = False
count = 0
for i in range(150):
    try:
        resp = requests.post(url, headers=headers, json=data, timeout=2)
        if resp.status_code == 429:
            limited = True
            break
        count += 1
    except:
        pass
if limited:
    print(f'SUCCESS: Rate limit hit after {count} requests')
else:
    print('FAIL: No 429 response received.')
    sys.exit(1)
"
docker exec "$CONTAINER_ID" python -c "$PY_RATELIMIT" && log_pass "Rate limiting active." || log_fail "Rate limiting NOT triggered."

# ---------------------------------------------------------

section "PHASE 7: Infrastructure Check"
log_info "Description: Verify that the Gateway service is replicated (at least 2 replicas)."
log_info "Verifying API Gateway Replication..."
log_cmd "docker service ls --filter name=monitor-platform_gateway"
REPLICAS=$(docker service ls --filter name=monitor-platform_gateway --format "{{.Replicas}}")
log_info "Gateway Replicas: $REPLICAS"

if [[ "$REPLICAS" == "2/2" ]]; then
    log_pass "Gateway is replicated (2/2)."
elif [[ "$REPLICAS" == "1/1" ]]; then
    log_fail "Gateway is NOT replicated (1/1). Spec requires replication."
else
    # Could be "1/2" (converging)
    log_info "Gateway replication status is $REPLICAS. (If 2/2, it passes)."
fi

# ---------------------------------------------------------

section "PHASE 8: Load Testing (50 Nodes)"
log_info "Description: Verify system stability by simulating 50 concurrent nodes."
log_info "Simulating 50 concurrent nodes sending data for 30 seconds..."
log_info "Metric: CPU, Mem, Process Count per node."

# Copy load script to container (simplest way to run python with requests)
# Actually, we can just cat it into a python -c or copy the file
# Since we are using an existing container, let's use docker cp
log_cmd "docker cp tests/load_test.py $CONTAINER_ID:/tmp/load_test.py"
docker cp tests/load_test.py $CONTAINER_ID:/tmp/load_test.py

log_cmd "docker exec $CONTAINER_ID python /tmp/load_test.py \"$TOKEN\""
docker exec $CONTAINER_ID python /tmp/load_test.py "$TOKEN"
if [ $? -eq 0 ]; then
    log_pass "Load Test Passed (Infrastructure robust)."
else
    log_fail "Load Test Failed."
fi


# ---------------------------------------------------------

section "PHASE 9: Presentation Scenarios Validation"
log_info "Description: Verify Replication, Error Handling, Security, and DB Consistency."
log_info "Waiting 65s for Rate Limit window to reset after Load Test..."
sleep 65

# Copy validation script to container
log_cmd "docker cp tests/validate_presentation.py $CONTAINER_ID:/tmp/validate_presentation.py"
docker cp tests/validate_presentation.py $CONTAINER_ID:/tmp/validate_presentation.py

log_cmd "docker exec $CONTAINER_ID python /tmp/validate_presentation.py \"$TOKEN\""
docker exec $CONTAINER_ID python /tmp/validate_presentation.py "$TOKEN"
if [ $? -eq 0 ]; then
    log_pass "Presentation Scenarios Passed."
else
    log_fail "Presentation Scenarios Failed."
fi

# ================= MANUAL GUIDE =================

section "MANUAL VERIFICATION STEPS"
echo "The following steps require you to open a browser."
echo ""

echo "Step 1: Verify Grafana Dashboards"
echo "   - Open: $GRAFANA_URL"
echo "   - Login: admin / admin"
echo "   - Action: Go to 'Dashboards' -> 'NodeSense Metrics'"
read -p "   [Press Enter when verified]"
echo ""

echo "Step 2: Verify Persistence (Full Spec)"
echo "   - Action: Sampling DB for 'spec-test-node' metrics."
docker exec -it $DB_CONTAINER psql -U nodesense -d nodesense -c "SELECT time, node_id, metric_name, value FROM metrics WHERE node_id='spec-test-node' ORDER BY time DESC LIMIT 5;"
read -p "   [Press Enter to finish]"

section "Spec Alignment Verification Completed"
log_pass "All automated and manual steps concluded."

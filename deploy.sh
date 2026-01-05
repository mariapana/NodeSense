#!/bin/bash

set -e

# ================= BANNER =================
echo "=============================================================================="
echo "███╗   ██╗ ██████╗ ██████╗ ███████╗███████╗███████╗███╗   ██╗███████╗███████╗"
echo "████╗  ██║██╔═══██╗██╔══██╗██╔════╝██╔════╝██╔════╝████╗  ██║██╔════╝██╔════╝"
echo "██╔██╗ ██║██║   ██║██║  ██║█████╗  ███████╗█████╗  ██╔██╗ ██║███████╗█████╗"
echo "██║╚██╗██║██║   ██║██║  ██║██╔══╝  ╚════██║██╔══╝  ██║╚██╗██║╚════██║██╔══╝"
echo "██║ ╚████║╚██████╔╝██████╔╝███████╗███████║███████╗██║ ╚████║███████║███████╗"
echo "╚═╝  ╚═══╝ ╚═════╝ ╚═════╝ ╚══════╝╚══════╝╚══════╝╚═╝  ╚═══╝╚══════╝╚══════╝"
echo "=============================================================================="
echo "                           N O D E   M O N I T O R I N G   P L A T F O R M"
echo ""

# =============== LOGGING HELPERS =================
info() { echo -e "\e[34m[INFO]\e[0m $1"; }
ok()   { echo -e "\e[32m[OK]\e[0m $1"; }
err()  { echo -e "\e[31m[ERROR]\e[0m $1"; }
fail() { err "$1"; exit 1; }

STACK_NAME="monitor-platform"
STACK_FILE="stack.yml"
NETWORKS=("keycloak_net" "backend_net" "monitoring_net")
REALM_TEMPLATE="keycloak/import/NodeSense-realm.template.json"
REALM_SCRIPT="keycloak/generate-realm-json.sh"
COLLECTOR_IMAGE="nodesense-collector:latest"
COLLECTOR_DIR="collector"

# =============== CHECK DOCKER =================
info "Checking if Docker is running..."
docker info > /dev/null 2>&1 || fail "Docker is not running or not accessible."
ok "Docker is running."

# =============== CHECK SWARM ==================
info "Checking Docker Swarm status..."
SWARM=$(docker info --format '{{.Swarm.LocalNodeState}}')
[ "$SWARM" != "active" ] && fail "Docker Swarm is not active. Run setup.sh first."
ok "Swarm is active."

# =============== CHECK NETWORKS ===============
for NET in "${NETWORKS[@]}"; do
    info "Checking network $NET..."
    docker network ls | grep -q "$NET" || fail "Network $NET does not exist. Run setup.sh first."
    ok "Network $NET OK."
done

# =============== CHECK STACK FILE =============
info "Checking if $STACK_FILE exists..."
[ ! -f "$STACK_FILE" ] && fail "$STACK_FILE not found!"
ok "$STACK_FILE found."

# =============== CHECK TEMPLATE & SCRIPT =============
info "Checking Keycloak realm template..."
[ ! -f "$REALM_TEMPLATE" ] && fail "Realm template missing: $REALM_TEMPLATE"
ok "Template OK."

info "Checking realm generation script..."
[ ! -x "$REALM_SCRIPT" ] && fail "Realm generator missing or not executable: $REALM_SCRIPT"
ok "Generator OK."

# =============== CHECK COLLECTOR DIRECTORY ===============
info "Checking collector directory..."
[ ! -d "$COLLECTOR_DIR" ] && fail "Collector directory missing: $COLLECTOR_DIR"
[ ! -f "$COLLECTOR_DIR/Dockerfile" ] && fail "Collector Dockerfile missing!"
ok "Collector directory OK."

# =============== BUILD COLLECTOR IMAGE (SWARM IGNORES build:) ===============
info "Building collector image ($COLLECTOR_IMAGE)..."
docker build -t "$COLLECTOR_IMAGE" "$COLLECTOR_DIR" \
  || fail "Failed to build collector image"
ok "Collector image built."

docker image inspect "$COLLECTOR_IMAGE" > /dev/null 2>&1 \
  || fail "Collector image missing after build."
ok "Collector image exists."

# =============== BUILD AGENT IMAGE =================
AGENT_IMAGE="nodesense-agent:latest"
AGENT_DIR="agent"

info "Building agent image ($AGENT_IMAGE)..."
docker build -t "$AGENT_IMAGE" "$AGENT_DIR" \
  || fail "Failed to build agent image"
ok "Agent image built."

# =============== BUILD GATEWAY IMAGE =================
GATEWAY_IMAGE="nodesense-gateway:latest"
GATEWAY_DIR="gateway"

info "Building gateway image ($GATEWAY_IMAGE)..."
docker build -t "$GATEWAY_IMAGE" "$GATEWAY_DIR" \
  || fail "Failed to build gateway image"
ok "Gateway image built."

# =============== ASK FOR PASSWORDS & CLIENT SECRET =================
echo ""
echo "-------------------------------------------------------------"
echo "                 Keycloak Authentication Setup"
echo "-------------------------------------------------------------"

# --- Admin password ---
while true; do
    read -s -p "Admin password: " ADMIN_PASS
    echo ""
    read -s -p "Confirm admin password: " ADMIN_PASS2
    echo ""
    [ "$ADMIN_PASS" = "$ADMIN_PASS2" ] && [ -n "$ADMIN_PASS" ] && break
    echo "Passwords do not match or are empty. Try again."
done

# --- Viewer password ---
while true; do
    read -s -p "Viewer password: " VIEWER_PASS
    echo ""
    read -s -p "Confirm viewer password: " VIEWER_PASS2
    echo ""
    [ "$VIEWER_PASS" = "$VIEWER_PASS2" ] && [ -n "$VIEWER_PASS" ] && break
    echo "Passwords do not match or are empty. Try again."
done

# --- Client Secret ---
while true; do
    read -s -p "API Gateway client secret: " CLIENT_SECRET
    echo ""
    read -s -p "Confirm client secret: " CLIENT_SECRET2
    echo ""
    [ "$CLIENT_SECRET" = "$CLIENT_SECRET2" ] && [ -n "$CLIENT_SECRET" ] && break
    echo "Client secrets do not match or are empty. Try again."
done

echo ""
info "Generating private realm JSON..."

"$REALM_SCRIPT" "$ADMIN_PASS" "$VIEWER_PASS" "$CLIENT_SECRET" \
    || fail "Failed to generate realm JSON."

ok "Realm JSON generated successfully."
echo ""

# ================== DEPLOY ====================
info "Deploying stack: $STACK_NAME..."

docker stack deploy -c "$STACK_FILE" "$STACK_NAME" \
    || fail "Stack deployment failed!"

ok "Stack submitted. Waiting for services to start..."

# =============== VERIFY SERVICES WITH RETRIES ==============
MAX_RETRIES=60
SLEEP_TIME=2

info "Verifying service replicas (timeout: $((MAX_RETRIES * SLEEP_TIME))s)..."

SERVICES=$(docker stack services "$STACK_NAME" --format '{{.Name}}')

for SVC in $SERVICES; do
    info "Checking $SVC..."
    
    SUCCESS=0
    for ((i=1; i<=MAX_RETRIES; i++)); do
        
        REPLICAS_RAW=$(docker service ls --filter name="$SVC" --format '{{.Replicas}}')
        
        READY=$(echo "$REPLICAS_RAW" | cut -d'/' -f1)
        TOTAL=$(echo "$REPLICAS_RAW" | cut -d'/' -f2)

        if [[ "$READY" == "$TOTAL" ]]; then
            ok "$SVC is running ($READY/$TOTAL)"
            SUCCESS=1
            break
        fi
        
        info "$SVC not ready yet ($READY/$TOTAL) - retrying ($i/$MAX_RETRIES)..."
        sleep "$SLEEP_TIME"
    done

    if [[ "$SUCCESS" -ne 1 ]]; then
        fail "$SVC failed to reach Running state after timeout."
    fi
done

ok "All services are up and running!"
echo ""

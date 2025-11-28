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
echo "============================================================================="
echo "                           N O D E   M O N I T O R I N G   P L A T F O R M"
echo ""

# =============== LOGGING HELPERS =================
info() { echo -e "\e[34m[INFO]\e[0m $1"; }
ok()   { echo -e "\e[32m[OK]\e[0m $1"; }
err()  { echo -e "\e[31m[ERROR]\e[0m $1"; }
fail() { err "$1"; exit 1; }

STACK_NAME="monitor-platform"
STACK_FILE="stack.yml"
NETWORKS=("frontend_net" "backend_net" "monitoring_net")

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

# ================== DEPLOY ====================
info "Deploying stack: $STACK_NAME..."

docker stack deploy -c "$STACK_FILE" "$STACK_NAME" \
    || fail "Stack deployment failed!"

ok "Stack submitted. Waiting for services to start..."

# =============== VERIFY SERVICES WITH RETRIES ==============
MAX_RETRIES=30
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

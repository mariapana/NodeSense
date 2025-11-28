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
NETWORKS=("frontend_net" "backend_net" "monitoring_net")

# ================= CONFIRM ======================
echo -n "Are you sure you want to remove the stack and networks? (y/N): "
read -r CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    info "Cleanup cancelled."
    exit 0
fi

# =============== CHECK DOCKER ===================
info "Checking if Docker is running..."
docker info > /dev/null 2>&1 || fail "Docker is not running."
ok "Docker running."

# ================= REMOVE STACK =================
info "Removing stack: $STACK_NAME..."

docker stack rm "$STACK_NAME" || fail "Failed to remove stack."

ok "Stack removed. Waiting for cleanup..."
sleep 5

# =============== REMOVE NETWORKS ================
for NET in "${NETWORKS[@]}"; do
    info "Removing network $NET..."
    docker network rm "$NET" > /dev/null 2>&1 && ok "Removed $NET" || info "$NET already removed or not found."
done

# ================= LEAVE SWARM ==================
info "Leaving Docker Swarm..."
docker swarm leave --force > /dev/null 2>&1 || fail "Failed to leave swarm."

ok "Left Docker Swarm."

echo ""
ok "Cleanup complete!"


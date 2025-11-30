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

echo -n "Are you sure you want to remove EVERYTHING (stack, networks, volumes)? (y/N): "
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
docker stack rm "$STACK_NAME" || info "Stack already removed."
ok "Stack removed. Waiting for service shutdown..."
sleep 5

# =============== REMOVE NETWORKS ================
for NET in "${NETWORKS[@]}"; do
    info "Removing network $NET..."
    docker network rm "$NET" > /dev/null 2>&1 && ok "Removed $NET" || info "$NET already removed or not found."
done

# =============== REMOVE CONTAINERS LEFT BEHIND ================
info "Removing leftover containers..."
LEFTOVER_CONTAINERS=$(docker ps -a --filter "name=$STACK_NAME" -q)

if [ -n "$LEFTOVER_CONTAINERS" ]; then
    docker rm -f $LEFTOVER_CONTAINERS && ok "Leftover containers removed."
else
    info "No leftover containers."
fi

# =============== REMOVE VOLUMES (IMPORTANT) ====================
info "Searching for volumes related to stack: $STACK_NAME"

VOLUMES=$(docker volume ls --format '{{.Name}}' | grep "$STACK_NAME" || true)

if [ -z "$VOLUMES" ]; then
    info "No volumes found for stack."
else
    for VOL in $VOLUMES; do
        info "Force-removing any container using volume: $VOL"
        CONTAINERS_USING_VOL=$(docker ps -a --filter volume="$VOL" -q)

        if [ -n "$CONTAINERS_USING_VOL" ]; then
            docker rm -f $CONTAINERS_USING_VOL > /dev/null 2>&1
            ok "Removed containers blocking $VOL"
        fi

        info "Removing volume $VOL..."
        docker volume rm "$VOL" > /dev/null 2>&1 && ok "Removed $VOL" || err "Failed to remove $VOL"
    done
fi

# =============== OPTIONAL VOLUME PRUNE =================
echo -n "Remove ALL unused Docker volumes as well? (y/N): "
read -r RM_UNUSED
if [[ "$RM_UNUSED" == "y" || "$RM_UNUSED" == "Y" ]]; then
    info "Removing unused volumes..."
    docker volume prune -f
    ok "Unused volumes removed."
fi

# ================= LEAVE SWARM ==================
info "Leaving Docker Swarm..."
docker swarm leave --force > /dev/null 2>&1 || info "Already left swarm."
ok "Left Docker Swarm."

echo ""
ok "FULL CLEANUP COMPLETE — STACK, NETWORKS, CONTAINERS & VOLUMES REMOVED!"

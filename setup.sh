#!/bin/bash

set -e

# Colored logging functions
info() { echo -e "\e[34m[INFO]\e[0m $1"; }
ok()   { echo -e "\e[32m[OK]\e[0m $1"; }
err()  { echo -e "\e[31m[ERROR]\e[0m $1"; }

# Controlled exit on failure
fail() {
  err "$1"
  exit 1
}

echo "=============================================================================="
echo "███╗   ██╗ ██████╗ ██████╗ ███████╗███████╗███████╗███╗   ██╗███████╗███████╗"
echo "████╗  ██║██╔═══██╗██╔══██╗██╔════╝██╔════╝██╔════╝████╗  ██║██╔════╝██╔════╝"
echo "██╔██╗ ██║██║   ██║██║  ██║█████╗  ███████╗█████╗  ██╔██╗ ██║███████╗█████╗"
echo "██║╚██╗██║██║   ██║██║  ██║██╔══╝  ╚════██║██╔══╝  ██║╚██╗██║╚════██║██╔══╝"
echo "██║ ╚████║╚██████╔╝██████╔╝███████╗███████║███████╗██║ ╚████║███████║███████╗"
echo "╚═╝  ╚═══╝ ╚═════╝ ╚═════╝ ╚══════╝╚══════╝╚══════╝╚═╝  ╚═══╝╚══════╝╚══════╝"
echo "============================================================================="
echo "                           N O D E   M O N I T O R I N G   P L A T F O R M"

echo "--------------------------------------"
echo "       DOCKER SWARM SETUP SCRIPT"
echo "--------------------------------------"

### STEP 0 - Check if Docker daemon is running
info "Checking if Docker is running..."

if ! docker info > /dev/null 2>&1; then
    fail "Docker is not running or not accessible. 
Please ensure:
  - Docker daemon is started
  - Your user has permission to run Docker (e.g., part of docker group)"
fi

ok "Docker is running."

### STEP 1 - Initialize Swarm
info "Checking Swarm status..."

SWARM_STATUS=$(docker info --format '{{.Swarm.LocalNodeState}}')

if [ "$SWARM_STATUS" == "active" ]; then
    ok "Swarm is already active."
else
    info "Swarm is not active. Initializing..."
    docker swarm init --advertise-addr "$(hostname -I | awk '{print $1}')" > /dev/null 2>&1 \
        || fail "Failed to initialize Docker Swarm!"
    ok "Swarm initialized successfully."
fi

### STEP 2 - Create overlay networks
NETWORKS=("frontend_net" "backend_net" "monitoring_net")

for NET in "${NETWORKS[@]}"; do
    info "Checking network $NET..."
    if docker network ls | grep -q "$NET"; then
        ok "Network $NET already exists."
    else
        info "Creating overlay network $NET..."
        docker network create --driver overlay "$NET" > /dev/null 2>&1 \
            || fail "Failed to create network $NET!"
        ok "Network $NET created."
    fi
done

echo ""
ok "All networks created/verified successfully."

### STEP 3 - Final validation
info "Performing final validation..."

docker info --format '{{.Swarm.LocalNodeState}}' | grep -q "active" \
    || fail "Swarm is not functional!"

for NET in "${NETWORKS[@]}"; do
    docker network ls | grep -q "$NET" \
        || fail "Network $NET is missing!"
done

ok "Setup complete! Docker Swarm and networks are ready."
echo "--------------------------------------"
echo "You can now run:"
echo "    > deploy.sh script"
echo "    > docker stack deploy -c stack.yml monitor-platform"
echo "--------------------------------------"


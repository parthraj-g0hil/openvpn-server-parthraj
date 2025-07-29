#!/bin/bash

# Load environment variables
set -a
source .env
set +a

echo "[*] Updating old-server.conf with subnet values..."

# Update 'server' line with TRUST_SUB
TRUST_BASE=$(echo "$TRUST_SUB" | cut -d'/' -f1)
sed -i "s|^server .*|server ${TRUST_BASE} 255.255.255.0|" ./config/old-server.conf

# Update 'route' line with GUEST_SUB
GUEST_BASE=$(echo "$GUEST_SUB" | cut -d'/' -f1)
sed -i "s|^route .*|route ${GUEST_BASE} 255.255.255.0|" ./config/old-server.conf

# Update 'push "route ..."' line with HOME_SUB
HOME_BASE=$(echo "$HOME_SUB" | cut -d'/' -f1)
sed -i 's|^push "route .*|push \"route '"${HOME_BASE}"' 255.255.255.0\"|' ./config/old-server.conf

echo "[✔] Subnets updated in config/old-server.conf"

echo "[*] Starting Docker Compose..."
docker-compose up -d

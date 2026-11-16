#!/usr/bin/env bash
set -euo pipefail

CHAIN="HW4-EGRESS"

# Unlink custom chain from DOCKER-USER
while iptables -C DOCKER-USER -j "$CHAIN" 2>/dev/null; do
    iptables -D DOCKER-USER -j "$CHAIN"
done

# Flush and delete the custom chain without touching Docker's own rules
if iptables -L "$CHAIN" -n >/dev/null 2>&1; then
    iptables -F "$CHAIN"
    iptables -X "$CHAIN"
fi

echo "Removed $CHAIN rules from DOCKER-USER."

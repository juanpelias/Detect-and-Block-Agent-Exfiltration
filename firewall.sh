#!/usr/bin/env bash
set -euo pipefail

# Enable netfilter hooks on Linux bridge frames so br-hw4 traffic traverses iptables
modprobe br_netfilter
sysctl -w net.bridge.bridge-nf-call-iptables=1

CHAIN="HW4-EGRESS"

# Remove any existing jump from DOCKER-USER so the script can be re-run safely
while iptables -C DOCKER-USER -j "$CHAIN" 2>/dev/null; do
    iptables -D DOCKER-USER -j "$CHAIN"
done

# Create or flush the custom chain
iptables -N "$CHAIN" 2>/dev/null || iptables -F "$CHAIN"

# Allow established and related return traffic
iptables -A "$CHAIN" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow agent-node (172.30.0.10) to reach web-lab (172.30.0.40) on TCP 8000
iptables -A "$CHAIN" -s 172.30.0.10 -d 172.30.0.40 -p tcp --dport 8000 -m conntrack --ctstate NEW -j ACCEPT

# Log and drop new connections from agent-node to mock-c2 (172.30.0.66) on TCP 8080
iptables -A "$CHAIN" -s 172.30.0.10 -d 172.30.0.66 -p tcp --dport 8080 -m conntrack --ctstate NEW -j LOG --log-prefix "HW4-C2-DROP: " --log-level 4
iptables -A "$CHAIN" -s 172.30.0.10 -d 172.30.0.66 -p tcp --dport 8080 -m conntrack --ctstate NEW -j DROP

# Drop all other new forwarded connections from agent-node (default-deny egress)
iptables -A "$CHAIN" -s 172.30.0.10 -m conntrack --ctstate NEW -j DROP

# Leave unrelated Docker traffic unchanged
iptables -A "$CHAIN" -j RETURN

# Jump to HW4-EGRESS at the top of DOCKER-USER before Docker's own rules
iptables -I DOCKER-USER 1 -j "$CHAIN"

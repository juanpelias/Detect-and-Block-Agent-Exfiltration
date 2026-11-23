# Detect and Block Agent Exfiltration (CSCE 465/765 HW4)

A small, fully simulated data-exfiltration incident that runs in a private Docker network. A mock "skill" on an agent container opens an unauthorized listener and, when triggered, sends a fake secret to a mock command-and-control server over plaintext HTTP. The lab then shows how to scan for it, capture it, block it with a firewall, and detect it with Suricata.

Everything is local and fake: no real secrets, no external servers, no real malware.

## Lab layout

| Container | IP | Role |
|---|---|---|
| `agent-node` | 172.30.0.10 | Runs the mock skill (listener on TCP 9009) |
| `web-lab` | 172.30.0.40:8000 | Serves `benign.html` and `adversarial.html` (prompt-injection marker) |
| `mock-c2` | 172.30.0.66:8080 | Receives the POST and stores it at `/data/received.bin` |

Network: `hw4net`, 172.30.0.0/24, bridge name `br-hw4`.

## Files

| File | Purpose |
|---|---|
| `docker-compose.yml`, `Dockerfile` | Build and start the three containers |
| `c2.py` | Mock C2 receiver (stores the POST body, returns 204) |
| `mock_skill.sh` | Opens the listener on 9009; with `exfiltrate-course-file`, POSTs `fake_secrets.txt` to mock-c2 |
| `fake_secrets.txt` | Unique fake token (no trailing newline) |
| `web/benign.html`, `web/adversarial.html` | Normal page and page containing `CSCE465-COURSE-MARKER` plus the injected instruction |
| `firewall.sh`, `firewall-reset.sh` | Default-deny egress for agent-node in the `DOCKER-USER` chain, and its removal |
| `local.rules` | Three Suricata rules (SIDs 1000001 to 1000003) |
| `report.pdf` | Report with evidence and the incident summary |
| `AI_USAGE.md` files | AI-use disclosures |

## Requirements

Ubuntu VM with Docker Engine and the Compose plugin, `nmap`, `tcpdump`, `tshark`, `netcat-openbsd` and `suricata`.

## Quick start

Run everything from this folder.

```bash
# 1. Start the lab
docker compose up -d --build
docker compose ps

# 2. Scan only the agent host (the listener on 9009 should show up)
nmap -sV -p 1-10000 172.30.0.10

# 3. Capture while reproducing the incident
sudo tcpdump -i br-hw4 -s 0 -w hw4-malicious.pcap 'net 172.30.0.0/24'     # terminal A
docker compose exec agent-node curl -s http://172.30.0.40:8000/adversarial.html   # terminal B
docker compose exec agent-node /app/mock_skill.sh exfiltrate-course-file          # terminal B
# Ctrl-C the capture, then compare hashes:
sha256sum fake_secrets.txt
docker compose exec mock-c2 sha256sum /data/received.bin

# 4. Clean baseline capture (benign request only) -> hw4-clean.pcap
sudo tcpdump -i br-hw4 -s 0 -w hw4-clean.pcap 'net 172.30.0.0/24'
docker compose exec agent-node curl -s http://172.30.0.40:8000/benign.html

# 5. Detect with Suricata (offline)
mkdir -p suricata-malicious suricata-clean
suricata -k none -r hw4-malicious.pcap -S local.rules -l suricata-malicious
suricata -k none -r hw4-clean.pcap -S local.rules -l suricata-clean
cat suricata-malicious/fast.log suricata-clean/fast.log

# 6. Block with the firewall, then remove it
sudo bash firewall.sh
sudo bash firewall-reset.sh
```

With the firewall loaded, the exfiltration to mock-c2 times out and no new `/data/received.bin` is written, while the benign fetch from web-lab and the reply from the 9009 listener still work. Blocked attempts are logged with the prefix `HW4-C2-DROP:` (`sudo dmesg | grep HW4-C2-DROP`).

## Notes

- `firewall.sh` loads `br_netfilter` and sets `net.bridge.bridge-nf-call-iptables=1`, which are needed for bridged container-to-container traffic to reach iptables. These settings do not survive a reboot.
- Capture on `br-hw4`, not `-i any`, to avoid duplicated packets.
- Run Suricata with `-k none`: checksums on Docker bridge captures are unfinished and would otherwise cause packets to be discarded.
- Run the capture and Suricata steps before loading the firewall, because the firewall blocks the exfiltration.
- Do not mount your home directory or the Docker socket into any container, and do not scan any address other than 172.30.0.10.

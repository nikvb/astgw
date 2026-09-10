#!/bin/bash
###############################################################################
# AstGW New Server Install Script
# Runs from the portal machine (5.9.21.179), SSHes into a new Debian 13 server
# and sets it up as an Asterisk 22 gateway node.
#
# Usage: bash install-server.sh <NEW_SERVER_IP> <SERVER_NAME>
###############################################################################
set -euo pipefail

# ── Argument check ──────────────────────────────────────────────────────────
if [ $# -lt 2 ]; then
    echo "Usage: $0 <NEW_SERVER_IP> <SERVER_NAME>"
    echo "  e.g. $0 203.0.113.10 primo-amd03"
    exit 1
fi

SERVER_IP="$1"
SERVER_NAME="$2"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Phase 1: Config (interactive or env-driven) ───────────────────────────
if [ "${ASTGW_NONINTERACTIVE:-}" = "1" ]; then
    DB_HOST="${ASTGW_DB_HOST:-5.9.21.179}"
    DB_PASS="${ASTGW_DB_PASS:-ast3r1sk_gw_2026}"
else
    read -rp "DB_HOST [5.9.21.179]: " DB_HOST
    DB_HOST="${DB_HOST:-5.9.21.179}"
    read -rsp "DB_PASS [ast3r1sk_gw_2026]: " DB_PASS
    echo
    DB_PASS="${DB_PASS:-ast3r1sk_gw_2026}"
fi

DB_USER="asterisk"
DB_NAME="asterisk_mgmt"
DB_PORT="5432"

# ── SSH helpers ─────────────────────────────────────────────────────────────
SSH_KEY="/root/.ssh/astgw-portal.key"
if [ ! -f "$SSH_KEY" ]; then
    SSH_KEY="/root/.ssh/id_rsa"
fi
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -i $SSH_KEY"

remote() {
    ssh $SSH_OPTS "root@${SERVER_IP}" "$@"
}

scp_to() {
    scp $SSH_OPTS "$1" "root@${SERVER_IP}:$2"
}

local_db() {
    PGPASSWORD="$DB_PASS" psql -U "$DB_USER" -d "$DB_NAME" -h "$DB_HOST" -p "$DB_PORT" -t -A -c "$1"
}

echo "============================================"
echo " AstGW New Server Install"
echo " Target:  $SERVER_IP ($SERVER_NAME)"
echo " DB Host: $DB_HOST"
echo " SSH Key: $SSH_KEY"
echo "============================================"

# Quick connectivity check
echo ">> Testing SSH to $SERVER_IP ..."
remote "hostname" || { echo "FATAL: Cannot SSH to $SERVER_IP"; exit 1; }

# ── Phase 2: Install OS dependencies ───────────────────────────────────────
echo ""
echo ">> Phase 2: Installing OS packages ..."
remote "export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -y \
        build-essential libpq-dev libedit-dev uuid-dev libxml2-dev \
        libsqlite3-dev libssl-dev libjansson-dev libncurses-dev \
        python3 python3-pip python3-dev \
        iptables-persistent wget curl"

echo ">> Installing Python packages ..."
remote "pip3 install --break-system-packages pyst2 websocket-client"

# ── Phase 3: Compile Asterisk 22 from source ───────────────────────────────
echo ""
echo ">> Phase 3: Compiling Asterisk 22 ..."
remote "cd /usr/src && \
    wget -q https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-22-current.tar.gz && \
    tar xzf asterisk-22-current.tar.gz && \
    cd asterisk-22.*/ && \
    contrib/scripts/install_prereq install && \
    ./configure --with-pjproject-bundled && \
    make menuselect.makeopts && \
    menuselect/menuselect --enable res_config_pgsql --enable res_pjsip --enable res_pjsip_endpoint_identifier_ip menuselect.makeopts && \
    make -j\$(nproc) && \
    make install && \
    make config && \
    make samples"

# Verify res_config_pgsql was compiled
remote "ls /usr/lib/asterisk/modules/res_config_pgsql.so" || {
    echo "FATAL: res_config_pgsql.so not found — PostgreSQL realtime will not work!"
    exit 1
}

# ── Phase 4: Write Asterisk config files ───────────────────────────────────
echo ""
echo ">> Phase 4: Writing Asterisk configuration ..."

# Raise file descriptor limit — Asterisk resets its own limit via asterisk.conf
remote "sed -i 's/;maxfiles = 1000/maxfiles = 65536/' /etc/asterisk/asterisk.conf"
# Also set ulimit in init script as a belt-and-suspenders backup
remote "grep -q 'ulimit -n 65536' /etc/init.d/asterisk || sed -i 's|start-stop-daemon --start --oknodo --exec \$DAEMON -- \$ASTARGS|ulimit -n 65536\n\tstart-stop-daemon --start --oknodo --exec \$DAEMON -- \$ASTARGS|' /etc/init.d/asterisk"

# res_pgsql.conf
remote "cat > /etc/asterisk/res_pgsql.conf << 'CFGEOF'
[general]
dbhost=${DB_HOST}
dbport=${DB_PORT}
dbname=${DB_NAME}
dbuser=${DB_USER}
dbpass=${DB_PASS}
dbappname=asterisk
CFGEOF"

# extconfig.conf
remote "cat > /etc/asterisk/extconfig.conf << 'CFGEOF'
[settings]
ps_endpoints => pgsql,general,ps_endpoints
ps_aors => pgsql,general,ps_aors
ps_endpoint_id_ips => pgsql,general,ps_endpoint_id_ips
CFGEOF"

# sorcery.conf
remote "cat > /etc/asterisk/sorcery.conf << 'CFGEOF'
[res_pjsip]
endpoint=config,pjsip.conf,criteria=type=endpoint
endpoint=realtime,ps_endpoints
auth=config,pjsip.conf,criteria=type=auth
aor=config,pjsip.conf,criteria=type=aor
aor=realtime,ps_aors
domain_alias=config,pjsip.conf,criteria=type=domain_alias
contact=astdb,registrator
global=config,pjsip.conf,criteria=type=global
system=config,pjsip.conf,criteria=type=system
transport=config,pjsip.conf,criteria=type=transport

[res_pjsip_endpoint_identifier_ip]
identify=config,pjsip.conf,criteria=type=identify
identify=realtime,ps_endpoint_id_ips
CFGEOF"

# pjsip.conf — copy from local files
scp_to "${SCRIPT_DIR}/pjsip.conf" "/etc/asterisk/pjsip.conf"

# extensions.conf — copy from local files
scp_to "${SCRIPT_DIR}/extensions.conf" "/etc/asterisk/extensions.conf"

# amd.conf
remote "cat > /etc/asterisk/amd.conf << 'CFGEOF'
[general]
initial_silence=2500
greeting=1500
after_greeting_silence=800
total_analysis_time=5000
min_word_length=100
between_words_silence=50
maximum_number_of_words=3
silence_threshold=256
maximum_word_length=5000
CFGEOF"

# logger.conf — copy from local files (single source of truth)
scp_to "${SCRIPT_DIR}/logger.conf" "/etc/asterisk/logger.conf"

# Log rotation. Without this, full.log grows without bound — debug-level
# logging on a busy switch has produced 60 GB files. Rotation is checked
# hourly as well as daily, because 500 MB can be reached well inside a day.
scp_to "${SCRIPT_DIR}/logrotate-asterisk" "/etc/logrotate.d/asterisk"
scp_to "${SCRIPT_DIR}/cron-hourly-asterisk-logrotate" "/etc/cron.hourly/asterisk-logrotate"
remote "chmod 0644 /etc/logrotate.d/asterisk && \
    chmod 0755 /etc/cron.hourly/asterisk-logrotate && \
    logrotate -d /etc/logrotate.d/asterisk > /dev/null"

# modules.conf
remote "cat > /etc/asterisk/modules.conf << 'CFGEOF'
[modules]
autoload=yes
CFGEOF"

# ── Phase 5: Deploy AMD script ─────────────────────────────────────────────
echo ""
echo ">> Phase 5: Deploying AMD AGI script ..."
scp_to "${SCRIPT_DIR}/amd.py" "/var/lib/asterisk/agi-bin/amd.py"
remote "chmod +x /var/lib/asterisk/agi-bin/amd.py && \
    python3 -m py_compile /var/lib/asterisk/agi-bin/amd.py && \
    mkdir -p /var/log/amd"

# Per-client gateway routing AGI — extensions.conf [gw-route] calls this, so a
# server without it would fall back to voip-switch for every client.
scp_to "${SCRIPT_DIR}/gateway_select.py" "/var/lib/asterisk/agi-bin/gateway_select.py"
remote "chmod +x /var/lib/asterisk/agi-bin/gateway_select.py && \
    python3 -m py_compile /var/lib/asterisk/agi-bin/gateway_select.py"

# Routing test harness — included by extensions.conf, places no calls.
#   asterisk -rx 'dialplan set global TESTIP <client ip>'
#   asterisk -rx 'channel originate Local/s@gw-route-test application Wait 1'
scp_to "${SCRIPT_DIR}/extensions_gwtest.conf" "/etc/asterisk/extensions_gwtest.conf"

# ── Phase 6: iptables baseline ─────────────────────────────────────────────
echo ""
echo ">> Phase 6: Setting up iptables baseline ..."
remote "iptables -F INPUT

# Base rules
iptables -P INPUT DROP
iptables -A INPUT -i lo -j ACCEPT -m comment --comment 'LOCAL: loopback'
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT -m comment --comment 'STATE: established/related'

# Public services
iptables -A INPUT -p tcp --dport 444 -j ACCEPT -m comment --comment 'PUBLIC: Primo Whitelist TCP 444'

# Carrier - ConnexCS
iptables -A INPUT -s 138.68.143.62  -p udp -j ACCEPT -m comment --comment 'Carrier - ConnexCS'
iptables -A INPUT -s 46.101.132.35  -p udp -j ACCEPT -m comment --comment 'Carrier - ConnexCS'
iptables -A INPUT -s 46.101.117.130 -p udp -j ACCEPT -m comment --comment 'Carrier - ConnexCS'
iptables -A INPUT -s 178.62.116.211 -p udp -j ACCEPT -m comment --comment 'Carrier - ConnexCS'
iptables -A INPUT -s 188.166.150.161 -p udp -j ACCEPT -m comment --comment 'Carrier - ConnexCS'
iptables -A INPUT -s 139.59.78.170  -p udp -j ACCEPT -m comment --comment 'Carrier - ConnexCS'
iptables -A INPUT -s 45.132.15.40   -p udp -j ACCEPT -m comment --comment 'Carrier - ConnexCS'
iptables -A INPUT -s 192.241.173.22 -p udp -j ACCEPT -m comment --comment 'Carrier - ConnexCS'
iptables -A INPUT -s 139.59.178.177 -p udp -j ACCEPT -m comment --comment 'Carrier - ConnexCS'
iptables -A INPUT -s 206.81.11.139  -p udp -j ACCEPT -m comment --comment 'Carrier - ConnexCS'
iptables -A INPUT -s 178.62.3.137   -p udp -j ACCEPT -m comment --comment 'Carrier - ConnexCS'
iptables -A INPUT -s 178.62.35.235  -p udp -j ACCEPT -m comment --comment 'Carrier - ConnexCS'
iptables -A INPUT -s 178.62.19.113  -p udp -j ACCEPT -m comment --comment 'Carrier - ConnexCS'
iptables -A INPUT -s 178.62.29.244  -p udp -j ACCEPT -m comment --comment 'Carrier - ConnexCS'
iptables -A INPUT -s 178.62.19.114  -p udp -j ACCEPT -m comment --comment 'Carrier - ConnexCS'
iptables -A INPUT -s 178.62.124.163 -p udp -j ACCEPT -m comment --comment 'Carrier - ConnexCS'
iptables -A INPUT -s 162.243.64.233 -p udp -j ACCEPT -m comment --comment 'Carrier - ConnexCS'
iptables -A INPUT -s 104.131.42.30  -p udp -j ACCEPT -m comment --comment 'Carrier - ConnexCS'
iptables -A INPUT -s 107.170.153.117 -p udp -j ACCEPT -m comment --comment 'Carrier - ConnexCS'
iptables -A INPUT -s 104.236.44.208 -p udp -j ACCEPT -m comment --comment 'Carrier - ConnexCS'
iptables -A INPUT -s 142.93.252.149 -p udp -j ACCEPT -m comment --comment 'Carrier - ConnexCS'
iptables -A INPUT -s 142.93.0.147   -p udp -j ACCEPT -m comment --comment 'Carrier - ConnexCS'
iptables -A INPUT -s 142.93.252.97  -p udp -j ACCEPT -m comment --comment 'Carrier - ConnexCS'

# Carrier - Peeredge
iptables -A INPUT -s 38.147.130.108 -p udp -j ACCEPT -m comment --comment 'Carrier - Peeredge'
iptables -A INPUT -s 38.147.130.109 -p udp -j ACCEPT -m comment --comment 'Carrier - Peeredge'
iptables -A INPUT -s 38.147.130.233 -p udp -j ACCEPT -m comment --comment 'Carrier - Peeredge'
iptables -A INPUT -s 38.147.130.243 -p udp -j ACCEPT -m comment --comment 'Carrier - Peeredge'
iptables -A INPUT -s 38.65.82.87    -p udp -j ACCEPT -m comment --comment 'Carrier - Peeredge'
iptables -A INPUT -s 38.65.82.88    -p udp -j ACCEPT -m comment --comment 'Carrier - Peeredge'
iptables -A INPUT -s 38.68.21.30    -p udp -j ACCEPT -m comment --comment 'Carrier - Peeredge'
iptables -A INPUT -s 38.68.21.31    -p udp -j ACCEPT -m comment --comment 'Carrier - Peeredge'
iptables -A INPUT -s 38.68.21.32    -p udp -j ACCEPT -m comment --comment 'Carrier - Peeredge'

# Datacentre - DCP
iptables -A INPUT -s 77.237.250.0/24  -j ACCEPT -m comment --comment 'Datacentre - DCP'
iptables -A INPUT -s 185.70.11.0/24   -j ACCEPT -m comment --comment 'Datacentre - DCP'
iptables -A INPUT -s 185.70.9.128/26  -j ACCEPT -m comment --comment 'Datacentre - DCP'
iptables -A INPUT -s 10.0.0.0/16      -j ACCEPT -m comment --comment 'Datacentre - DCP'

# Hetzner monitoring
iptables -A INPUT -s 188.40.24.211   -p icmp -j ACCEPT -m comment --comment 'Hetzner Monitoring'
iptables -A INPUT -s 213.133.113.82  -p icmp -j ACCEPT -m comment --comment 'Hetzner Monitoring'
iptables -A INPUT -s 213.133.113.83  -p icmp -j ACCEPT -m comment --comment 'Hetzner Monitoring'
iptables -A INPUT -s 213.133.113.84  -p icmp -j ACCEPT -m comment --comment 'Hetzner Monitoring'
iptables -A INPUT -s 213.133.113.86  -p icmp -j ACCEPT -m comment --comment 'Hetzner Monitoring'
iptables -A INPUT -s 88.99.105.21    -p icmp -j ACCEPT -m comment --comment 'Hetzner Monitoring'
iptables -A INPUT -s 168.119.4.168   -p icmp -j ACCEPT -m comment --comment 'Hetzner Monitoring'
iptables -A INPUT -s 138.201.38.53   -p icmp -j ACCEPT -m comment --comment 'Hetzner Monitoring'

# Primo / Office
iptables -A INPUT -s 138.68.152.190  -j ACCEPT -m comment --comment 'Primo - API'
iptables -A INPUT -s 135.181.254.177 -j ACCEPT -m comment --comment 'Primo - Control'
iptables -A INPUT -s 88.99.213.88    -j ACCEPT -m comment --comment 'Primo - Sentinel'
iptables -A INPUT -s 209.97.141.182  -j ACCEPT -m comment --comment 'Primo - DEV'
iptables -A INPUT -s 138.201.253.50  -j ACCEPT -m comment --comment 'Primo - DID Portal'
iptables -A INPUT -s 125.22.105.213  -j ACCEPT -m comment --comment 'Primo - India Office'
iptables -A INPUT -s 23.128.129.22   -j ACCEPT -m comment --comment 'Primo - Lucky'
iptables -A INPUT -s 77.237.250.135  -j ACCEPT -m comment --comment 'Primo - Monitoring'
iptables -A INPUT -s 103.83.89.40    -j ACCEPT -m comment --comment 'Primo - PK Office 1'
iptables -A INPUT -s 72.255.1.31     -j ACCEPT -m comment --comment 'Primo - PK Office 2'
iptables -A INPUT -s 103.83.91.128   -j ACCEPT -m comment --comment 'Primo - PK Office 3'
iptables -A INPUT -s 62.210.125.244  -j ACCEPT -m comment --comment 'Primo - Status'
iptables -A INPUT -s 185.73.39.246   -j ACCEPT -m comment --comment 'Primo - UK Office 1'
iptables -A INPUT -s 185.169.116.61  -j ACCEPT -m comment --comment 'Primo - UK Office 2'
iptables -A INPUT -s 77.237.248.234  -j ACCEPT -m comment --comment 'Primo - VPN 1'
iptables -A INPUT -s 77.237.248.235  -j ACCEPT -m comment --comment 'Primo - VPN 2'
iptables -A INPUT -s 77.237.248.248  -j ACCEPT -m comment --comment 'Primo - VPN 3'
iptables -A INPUT -s 173.208.219.162 -j ACCEPT -m comment --comment 'NIK AMDY'
iptables -A INPUT -s 187.150.56.223  -j ACCEPT -m comment --comment 'NIK AMDY'
iptables -A INPUT -s 23.88.115.231   -j ACCEPT -m comment --comment 'Primo - Zabbix'

# RTP + SSH (these go last, after client rules get inserted at position 68)
iptables -A INPUT -p udp --dport 10000:20000 -j ACCEPT -m comment --comment 'CATCHALL: RTP from unknown carriers'
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

iptables-save > /etc/iptables/rules.v4"

# ── Phase 7: Sync existing client firewall rules ───────────────────────────
echo ""
echo ">> Phase 7: Syncing client firewall rules from DB ..."
CLIENT_ROWS=$(local_db "SELECT name, ip FROM clients WHERE enabled = true ORDER BY id;")

if [ -n "$CLIENT_ROWS" ]; then
    while IFS='|' read -r cname cip; do
        cname_safe=$(echo "$cname" | tr -cd 'a-zA-Z0-9 _-')
        echo "   Adding client: $cname_safe ($cip)"
        remote "iptables -I INPUT 68 -s ${cip} -p udp --dport 5060 -j ACCEPT -m comment --comment 'AstGW: ${cname_safe}'"
    done <<< "$CLIENT_ROWS"
    remote "iptables-save > /etc/iptables/rules.v4"
    echo "   Synced $(echo "$CLIENT_ROWS" | wc -l) client rules."
else
    echo "   No enabled clients found in DB (or DB unreachable)."
fi

# ── Phase 8: Start Asterisk & verify ───────────────────────────────────────
echo ""
echo ">> Phase 8: Starting Asterisk ..."
remote "systemctl enable asterisk && systemctl start asterisk"
sleep 3

echo ""
echo ">> Verification:"
echo "--- module show like pgsql ---"
remote "asterisk -rx 'module show like pgsql'" || true
echo ""
echo "--- pjsip show endpoints ---"
remote "asterisk -rx 'pjsip show endpoints'" || true
echo ""
echo "--- iptables summary ---"
remote "iptables -L INPUT -n --line-numbers | head -5; echo '...'; iptables -L INPUT -n --line-numbers | tail -10"

# ── Phase 9: Register in portal DB & open PostgreSQL access ────────────────
echo ""
echo ">> Phase 9: Registering server in portal DB ..."

# Insert server record (skip if portal already inserted it)
if [ "${ASTGW_NONINTERACTIVE:-}" = "1" ]; then
    echo "   Server record already created by portal, skipping INSERT."
else
    local_db "INSERT INTO servers (name, ip, enabled) VALUES ('${SERVER_NAME}', '${SERVER_IP}', true);"
    echo "   Inserted into servers table."
fi

# Open PostgreSQL port on DB host firewall for new server
echo "   Opening port 5432 on DB host for $SERVER_IP ..."
ssh $SSH_OPTS "root@${DB_HOST}" \
    "iptables -I INPUT 3 -s ${SERVER_IP} -p tcp --dport 5432 -j ACCEPT -m comment --comment 'AstGW: ${SERVER_NAME} PostgreSQL' && iptables-save > /etc/iptables/rules.v4"

# Open firewall on every existing server for the new server, and vice versa
echo "   Opening firewall between new server and existing pool ..."
EXISTING_SERVERS=$(local_db "SELECT name, ip FROM servers WHERE enabled = true AND ip != '${SERVER_IP}';")

if [ -n "$EXISTING_SERVERS" ]; then
    while IFS='|' read -r sname sip; do
        [ -z "$sip" ] && continue
        echo "   >> $sname ($sip): allowing $SERVER_IP ..."
        ssh $SSH_OPTS "root@${sip}" \
            "iptables -I INPUT 3 -s ${SERVER_IP} -j ACCEPT -m comment --comment 'AstGW: ${SERVER_NAME}' && iptables-save > /etc/iptables/rules.v4" \
            && echo "      OK" || echo "      WARN: could not update $sname"

        echo "   >> $SERVER_NAME ($SERVER_IP): allowing $sip ..."
        remote "iptables -I INPUT 3 -s ${sip} -j ACCEPT -m comment --comment 'AstGW: ${sname}' && iptables-save > /etc/iptables/rules.v4" \
            && echo "      OK" || echo "      WARN: could not update $SERVER_NAME for $sname"
    done <<< "$EXISTING_SERVERS"
else
    echo "   No other servers in pool yet."
fi

echo ""
echo "============================================"
echo " Install complete: $SERVER_NAME ($SERVER_IP)"
echo "============================================"

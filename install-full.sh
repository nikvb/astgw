#!/bin/bash
###############################################################################
# AstGW Full Standalone Install Script
#
# Installs a complete self-contained AstGW cluster on a single Debian 13 server:
#   - PostgreSQL 17  (local DB for portal + Asterisk realtime)
#   - Asterisk 22    (compiled from source, PJSIP realtime via local PostgreSQL)
#   - AstGW Portal   (SvelteKit/Node, served via PM2 on port 3015)
#
# Run this from the machine that holds the astgw-files directory.
# The target server must be reachable via SSH as root.
#
# Usage: bash install-full.sh <SERVER_IP> <SERVER_NAME>
#   e.g. bash install-full.sh 203.0.113.10 cluster2-amd01
###############################################################################
set -euo pipefail

# ── Argument check ───────────────────────────────────────────────────────────
if [ $# -lt 2 ]; then
    echo "Usage: $0 <SERVER_IP> <SERVER_NAME>"
    echo "  e.g. $0 203.0.113.10 cluster2-amd01"
    exit 1
fi

SERVER_IP="$1"
SERVER_NAME="$2"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Config ───────────────────────────────────────────────────────────────────
if [ -n "${ASTGW_DB_PASS:-}" ]; then
    DB_PASS="$ASTGW_DB_PASS"
    PORTAL_PORT="${ASTGW_PORTAL_PORT:-3015}"
else
    read -rsp "DB password [ast3r1sk_gw_2026]: " DB_PASS; echo
    DB_PASS="${DB_PASS:-ast3r1sk_gw_2026}"
    read -rp "Portal port [3015]: " PORTAL_PORT
    PORTAL_PORT="${PORTAL_PORT:-3015}"
fi

DB_HOST="127.0.0.1"
DB_USER="asterisk"
DB_NAME="asterisk_mgmt"
DB_PORT="5432"
PORTAL_DIR="/root/astgw"

# ── SSH helpers ───────────────────────────────────────────────────────────────
SSH_KEY="${ASTGW_SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o IdentitiesOnly=yes -i $SSH_KEY"

remote() { ssh $SSH_OPTS "root@${SERVER_IP}" "$@"; }
scp_to() { scp -r $SSH_OPTS "$1" "root@${SERVER_IP}:$2"; }

echo "============================================"
echo " AstGW Full Standalone Install"
echo " Target:      $SERVER_IP ($SERVER_NAME)"
echo " Portal port: $PORTAL_PORT"
echo " SSH Key:     $SSH_KEY"
echo "============================================"

remote "hostname" || { echo "FATAL: Cannot SSH to $SERVER_IP"; exit 1; }

# ── Phase 1: OS packages ─────────────────────────────────────────────────────
echo ""
echo ">> Phase 1: Installing OS packages ..."
remote "export DEBIAN_FRONTEND=noninteractive && apt-get update -q && apt-get install -y \
    build-essential libpq-dev libedit-dev uuid-dev libxml2-dev \
    libsqlite3-dev libssl-dev libjansson-dev libncurses-dev \
    python3 python3-pip python3-dev \
    postgresql postgresql-client \
    iptables-persistent wget curl"

echo ">> Installing Python packages ..."
# --break-system-packages needs pip 23+. Ubuntu 22.04 ships pip 22, where the
# flag is an error and set -e would abort the install, so fall back.
remote "pip3 install --break-system-packages pyst2 websocket-client || \
    pip3 install pyst2 websocket-client"

# ── Phase 2: PostgreSQL setup ─────────────────────────────────────────────────
echo ""
echo ">> Phase 2: Setting up PostgreSQL ..."
remote "systemctl enable postgresql && systemctl start postgresql && sleep 2"

# Create DB user and database
remote "su -c \"psql -tc \\\"SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'\\\" | grep -q 1 || psql -c \\\"CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';\\\"\" postgres"
remote "su -c \"psql -tc \\\"SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'\\\" | grep -q 1 || psql -c \\\"CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};\\\"\" postgres"
remote "su -c \"psql -d ${DB_NAME} -c \\\"GRANT ALL ON SCHEMA public TO ${DB_USER};\\\"\" postgres"

# pg_hba: allow MD5 auth locally and from any Asterisk gateway node
remote "grep -q 'host ${DB_NAME} ${DB_USER} 0.0.0.0/0 md5' /etc/postgresql/*/main/pg_hba.conf \
    || echo 'host ${DB_NAME} ${DB_USER} 0.0.0.0/0 md5' >> /etc/postgresql/*/main/pg_hba.conf"
remote "grep -q 'local ${DB_NAME} ${DB_USER} md5' /etc/postgresql/*/main/pg_hba.conf \
    || echo 'local ${DB_NAME} ${DB_USER} md5' >> /etc/postgresql/*/main/pg_hba.conf"

# Allow remote connections (needed if additional gateway nodes are added later)
remote "sed -i \"s/#listen_addresses = 'localhost'/listen_addresses = '*'/\" /etc/postgresql/*/main/postgresql.conf 2>/dev/null || \
       sed -i \"s/listen_addresses = 'localhost'/listen_addresses = '*'/\" /etc/postgresql/*/main/postgresql.conf"
remote "systemctl reload postgresql"

# Create schema
remote "PGPASSWORD='${DB_PASS}' psql -U ${DB_USER} -d ${DB_NAME} -h 127.0.0.1" << SQLEOF
CREATE TABLE IF NOT EXISTS admin_users (
    id            SERIAL PRIMARY KEY,
    username      VARCHAR(100) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    created_at    TIMESTAMP DEFAULT now()
);
CREATE TABLE IF NOT EXISTS clients (
    id           SERIAL PRIMARY KEY,
    name         VARCHAR(100) NOT NULL,
    ip           VARCHAR(45)  NOT NULL UNIQUE,
    tech_prefix  VARCHAR(50)  NOT NULL,
    enabled      BOOLEAN DEFAULT true,
    created_at   TIMESTAMP DEFAULT now(),
    gateway_mode VARCHAR(16) DEFAULT 'weighted',
    amd_reject   VARCHAR(3) NOT NULL DEFAULT '603'
        CONSTRAINT clients_amd_reject_valid CHECK (amd_reject IN ('403', '603'))
);
-- Upstream SIP peers. endpoint = the PJSIP endpoint to dial; NULL means
-- 'gateway-<slug>'. is_default = used by any client with no assignment.
CREATE TABLE IF NOT EXISTS gateways (
    id         SERIAL PRIMARY KEY,
    name       VARCHAR(100) NOT NULL,
    ip         VARCHAR(45)  NOT NULL UNIQUE,
    port       INTEGER      NOT NULL DEFAULT 5060,
    weight     INTEGER      NOT NULL DEFAULT 1,
    enabled    BOOLEAN      NOT NULL DEFAULT true,
    created_at TIMESTAMP    NOT NULL DEFAULT now(),
    endpoint   VARCHAR(100),
    is_default BOOLEAN      NOT NULL DEFAULT false
);
CREATE UNIQUE INDEX IF NOT EXISTS gateways_single_default
    ON gateways (is_default) WHERE is_default;
CREATE TABLE IF NOT EXISTS client_gateways (
    id         SERIAL PRIMARY KEY,
    client_id  INTEGER NOT NULL REFERENCES clients(id)  ON DELETE CASCADE,
    gateway_id INTEGER NOT NULL REFERENCES gateways(id) ON DELETE CASCADE,
    weight     INTEGER DEFAULT 1,
    priority   INTEGER DEFAULT 1,
    UNIQUE (client_id, gateway_id)
);
CREATE INDEX IF NOT EXISTS idx_client_gateways_client ON client_gateways(client_id);
CREATE TABLE IF NOT EXISTS servers (
    id         SERIAL PRIMARY KEY,
    name       VARCHAR(100) NOT NULL,
    ip         VARCHAR(45)  NOT NULL,
    ssh_port   INTEGER DEFAULT 22,
    enabled    BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT now(),
    status     VARCHAR(20) DEFAULT 'online'
);
CREATE TABLE IF NOT EXISTS settings (
    key   VARCHAR(100) PRIMARY KEY,
    value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS ps_endpoints (
    id                  VARCHAR(40) PRIMARY KEY,
    transport           VARCHAR(40),
    aors                VARCHAR(200),
    auth                VARCHAR(40),
    context             VARCHAR(40),
    disallow            VARCHAR(200),
    allow               VARCHAR(200),
    direct_media        VARCHAR(10),
    direct_media_method VARCHAR(40),
    dtmf_mode           VARCHAR(40),
    force_rport         VARCHAR(10),
    ice_support         VARCHAR(10),
    identify_by         VARCHAR(80),
    rewrite_contact     VARCHAR(10),
    rtp_symmetric       VARCHAR(10),
    send_pai            VARCHAR(10),
    send_rpid           VARCHAR(10),
    callerid            VARCHAR(40),
    trust_id_inbound    VARCHAR(10),
    trust_id_outbound   VARCHAR(10),
    set_var             TEXT,
    deny                VARCHAR(95),
    permit              VARCHAR(95),
    language            VARCHAR(40),
    rtp_timeout         INTEGER,
    rtp_timeout_hold    INTEGER,
    mailboxes           VARCHAR(200)
);
CREATE TABLE IF NOT EXISTS ps_aors (
    id                 VARCHAR(40) PRIMARY KEY,
    contact            VARCHAR(255),
    default_expiration INTEGER,
    max_contacts       INTEGER,
    minimum_expiration INTEGER,
    remove_existing    VARCHAR(10),
    qualify_frequency  INTEGER
);
CREATE TABLE IF NOT EXISTS ps_endpoint_id_ips (
    id           VARCHAR(40) PRIMARY KEY,
    endpoint     VARCHAR(40),
    match        VARCHAR(80),
    srv_lookups  VARCHAR(10),
    match_header VARCHAR(255)
);
SQLEOF

echo "   Schema created."

# ── Phase 3: Compile Asterisk 22 ─────────────────────────────────────────────
echo ""
echo ">> Phase 3: Compiling Asterisk 22 (this takes 10-20 min) ..."
if remote "test -f /usr/sbin/asterisk" 2>/dev/null; then
    echo "   Asterisk already installed, skipping compile."
else
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
fi

remote "ls /usr/lib/asterisk/modules/res_config_pgsql.so" || {
    echo "FATAL: res_config_pgsql.so not found"
    exit 1
}

# ── Phase 4: Asterisk configuration ──────────────────────────────────────────
echo ""
echo ">> Phase 4: Writing Asterisk configuration ..."

# File descriptor limit
remote "sed -i 's/;maxfiles = 1000/maxfiles = 65536/' /etc/asterisk/asterisk.conf"
remote "grep -q 'ulimit -n 65536' /etc/init.d/asterisk || \
    sed -i 's|start-stop-daemon --start --oknodo --exec \$DAEMON -- \$ASTARGS|ulimit -n 65536\n\tstart-stop-daemon --start --oknodo --exec \$DAEMON -- \$ASTARGS|' /etc/init.d/asterisk"

# res_pgsql.conf (local DB)
remote "cat > /etc/asterisk/res_pgsql.conf" << CFGEOF
[general]
dbhost=127.0.0.1
dbport=${DB_PORT}
dbname=${DB_NAME}
dbuser=${DB_USER}
dbpass=${DB_PASS}
dbappname=asterisk
CFGEOF

# extconfig.conf
remote "cat > /etc/asterisk/extconfig.conf" << 'CFGEOF'
[settings]
ps_endpoints => pgsql,general,ps_endpoints
ps_aors => pgsql,general,ps_aors
ps_endpoint_id_ips => pgsql,general,ps_endpoint_id_ips
CFGEOF

# sorcery.conf
remote "cat > /etc/asterisk/sorcery.conf" << 'CFGEOF'
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
CFGEOF

# pjsip.conf and extensions.conf from local files
scp_to "${SCRIPT_DIR}/pjsip.conf" "/etc/asterisk/pjsip.conf"
scp_to "${SCRIPT_DIR}/extensions.conf" "/etc/asterisk/extensions.conf"

# Per-client gateway routing AGI. [gw-route] in extensions.conf calls this, so
# a node without it falls back to voip-switch for every client.
scp_to "${SCRIPT_DIR}/gateway_select.py" "/var/lib/asterisk/agi-bin/gateway_select.py"
remote "mkdir -p /var/lib/asterisk/agi-bin && \
    chmod +x /var/lib/asterisk/agi-bin/gateway_select.py && \
    python3 -m py_compile /var/lib/asterisk/agi-bin/gateway_select.py"

# Routing test harness. extensions.conf includes it, so the include fails
# without this file. It places no calls.
scp_to "${SCRIPT_DIR}/extensions_gwtest.conf" "/etc/asterisk/extensions_gwtest.conf"

# Log rotation. full.log grows without it; one node reached 58 GB.
scp_to "${SCRIPT_DIR}/logrotate-asterisk" "/etc/logrotate.d/asterisk"
scp_to "${SCRIPT_DIR}/cron-hourly-asterisk-logrotate" "/etc/cron.hourly/asterisk-logrotate"
remote "chmod 0644 /etc/logrotate.d/asterisk && \
    chmod 0755 /etc/cron.hourly/asterisk-logrotate"

# amd.conf
remote "cat > /etc/asterisk/amd.conf" << 'CFGEOF'
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
CFGEOF

# logger.conf
remote "cat > /etc/asterisk/logger.conf" << 'CFGEOF'
[general]
dateformat=%F %T.%3q

[logfiles]
console => notice,warning,error
messages => notice,warning,error
CFGEOF

# modules.conf
remote "cat > /etc/asterisk/modules.conf" << 'CFGEOF'
[modules]
autoload=yes
CFGEOF

# ── Phase 5: AMD AGI script ───────────────────────────────────────────────────
echo ""
echo ">> Phase 5: Deploying AMD AGI script ..."
scp_to "${SCRIPT_DIR}/amd.py" "/var/lib/asterisk/agi-bin/amd.py"
remote "chmod +x /var/lib/asterisk/agi-bin/amd.py && \
    python3 -m py_compile /var/lib/asterisk/agi-bin/amd.py && \
    mkdir -p /var/log/amd"

# ── Phase 6: iptables baseline ────────────────────────────────────────────────
echo ""
echo ">> Phase 6: Setting up iptables baseline ..."
remote "iptables -F INPUT
iptables -P INPUT DROP
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p udp --dport 10000:20000 -j ACCEPT -m comment --comment 'RTP'
iptables-save > /etc/iptables/rules.v4"

echo ""
echo "   NOTE: SIP port 5060 is intentionally NOT open globally."
echo "   Client IPs are added individually via the portal (UDP 5060 only)."
echo "   Add your carrier and office IPs manually or via the portal after install."

# ── Phase 7: Node.js 20 + PM2 ────────────────────────────────────────────────
echo ""
echo ">> Phase 7: Installing Node.js 20 + PM2 ..."
remote "curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    npm install -g pm2"

echo "   Node: $(remote node --version)"
echo "   npm:  $(remote npm --version)"

# ── Phase 7b: nginx reverse proxy (port 443 → portal) ────────────────────────
echo ""
echo ">> Phase 7b: Installing nginx for HTTPS on port 443 ..."
remote "apt-get install -y nginx openssl"

# Self-signed cert (replace with Let's Encrypt later if domain is available)
remote "mkdir -p /etc/nginx/ssl && openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/astgw.key \
    -out /etc/nginx/ssl/astgw.crt \
    -subj '/CN=${SERVER_IP}/O=AstGW/C=US' 2>/dev/null"

remote "cat > /etc/nginx/sites-available/astgw" << 'NGINXEOF'
server {
    listen 80;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    ssl_certificate     /etc/nginx/ssl/astgw.crt;
    ssl_certificate_key /etc/nginx/ssl/astgw.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    location / {
        proxy_pass         http://127.0.0.1:3015;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade $http_upgrade;
        proxy_set_header   Connection keep-alive;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
    }
}
NGINXEOF

remote "ln -sf /etc/nginx/sites-available/astgw /etc/nginx/sites-enabled/astgw && \
    rm -f /etc/nginx/sites-enabled/default && \
    nginx -t && systemctl enable nginx && systemctl restart nginx"

# ── Phase 8: Portal deploy + build ───────────────────────────────────────────
echo ""
echo ">> Phase 8: Deploying portal ..."

# Patch DB password in a temporary copy of db.ts if it differs from the hardcoded default
TMPDIR_PORTAL=$(mktemp -d)
cp -r "${SCRIPT_DIR}/src" "$TMPDIR_PORTAL/"
if [ "$DB_PASS" != "ast3r1sk_gw_2026" ]; then
    echo "   Patching DB password in src/lib/db.ts ..."
    sed -i "s/ast3r1sk_gw_2026/${DB_PASS}/g" "$TMPDIR_PORTAL/src/lib/db.ts"
fi

# Copy portal source from this repo to the new server and build
remote "mkdir -p ${PORTAL_DIR}"
scp_to "$TMPDIR_PORTAL/src"              "${PORTAL_DIR}/src"
scp_to "${SCRIPT_DIR}/package.json"      "${PORTAL_DIR}/package.json"
scp_to "${SCRIPT_DIR}/svelte.config.js"  "${PORTAL_DIR}/svelte.config.js"
scp_to "${SCRIPT_DIR}/tsconfig.json"     "${PORTAL_DIR}/tsconfig.json"
scp_to "${SCRIPT_DIR}/vite.config.ts"    "${PORTAL_DIR}/vite.config.ts"
[ -d "${SCRIPT_DIR}/static" ] && scp_to "${SCRIPT_DIR}/static" "${PORTAL_DIR}/static" \
    || remote "mkdir -p ${PORTAL_DIR}/static"
rm -rf "$TMPDIR_PORTAL"

echo "   Installing npm dependencies and building ..."
remote "cd ${PORTAL_DIR} && npm install && npm run build"

# ── Phase 9: SSH key for portal→Asterisk SSH ─────────────────────────────────
echo ""
echo ">> Phase 9: Generating SSH key for portal→Asterisk (localhost) ..."
remote "ssh-keygen -t ed25519 -f /root/.ssh/astgw-portal.key -N '' -C 'astgw-portal-${SERVER_NAME}' -q 2>/dev/null; true"
remote "cat /root/.ssh/astgw-portal.key.pub >> /root/.ssh/authorized_keys && \
    chmod 600 /root/.ssh/authorized_keys && \
    sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys"
remote "ssh -o StrictHostKeyChecking=no -i /root/.ssh/astgw-portal.key root@127.0.0.1 'echo SSH-OK' || true"

# ── Phase 10: Register server in its own DB ───────────────────────────────────
echo ""
echo ">> Phase 10: Registering server in local DB ..."
remote "PGPASSWORD='${DB_PASS}' psql -U ${DB_USER} -d ${DB_NAME} -h 127.0.0.1 \
    -c \"INSERT INTO servers (name, ip, status) VALUES ('${SERVER_NAME}', '${SERVER_IP}', 'online') ON CONFLICT DO NOTHING;\""

# Open PostgreSQL port to itself (Asterisk connects via 127.0.0.1 — already covered by loopback)
# No additional firewall rule needed for local-only setups.

# ── Phase 11: Start Asterisk + Portal ────────────────────────────────────────
echo ""
echo ">> Phase 11: Starting Asterisk ..."
remote "systemctl enable asterisk && systemctl start asterisk"
sleep 5

echo ""
echo ">> Phase 11: Starting portal via PM2 ..."
remote "cd ${PORTAL_DIR} && PORT=${PORTAL_PORT} HOST=0.0.0.0 \
    pm2 start build/index.js --name astgw && \
    pm2 save && \
    pm2 startup systemd -u root --hp /root | tail -1 | bash"

# ── Verification ──────────────────────────────────────────────────────────────
echo ""
echo ">> Verification:"
echo ""
echo "--- Asterisk version + pgsql module ---"
remote "asterisk -rx 'core show version'" || true
remote "asterisk -rx 'module show like pgsql'" || true
echo ""
echo "--- PJSIP endpoints ---"
remote "asterisk -rx 'pjsip show endpoints'" || true
echo ""
echo "--- PM2 status ---"
remote "pm2 list" || true
echo ""
echo "--- Open file limit ---"
remote "cat /proc/\$(ps aux | awk '/[u]sr.sbin.asterisk/{print \$2}' | head -1)/limits | grep 'open files'" || true

echo ""
echo "============================================"
echo " Install complete: $SERVER_NAME ($SERVER_IP)"
echo ""
echo " Portal: https://${SERVER_IP}  (self-signed cert)"
echo " Login:  admin / admin  (change after first login)"
echo ""
echo " Next steps:"
echo "  1. Log into the portal and configure Settings (carrier IP, SIP port)"
echo "  2. Update pjsip.conf with your carrier/voip-switch endpoint"
echo "  3. Add allowed IPs to iptables for your carriers and offices"
echo "============================================"

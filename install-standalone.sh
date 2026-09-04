#!/bin/bash
###############################################################################
# AstGW STANDALONE node installer  (self-contained, OS-aware)
#
# Unlike install-server.sh (which joins a node to the shared portal DB on
# 5.9.21.179), this script makes ONE host fully self-contained:
#   - local PostgreSQL on 127.0.0.1 holding its own realtime + registry schema
#   - Asterisk (PJSIP realtime) compiled from source
#   - firewall + AMD AGI script
# Nothing here talks to any other AstGW host.
#
# Handles both RHEL family (yum / firewalld / devtoolset) and Debian family
# (apt / iptables). Run AS ROOT, ON the target host.
#
#   bash install-standalone.sh
###############################################################################
set -uo pipefail

# ── Per-node config ──────────────────────────────────────────────────────────
NODE_NAME="aovatalk"
FQDN="sip.aovatalk.com"
NODE_IP="216.106.178.91"
DB_NAME="asterisk_mgmt"
DB_USER="asterisk"
DB_PASS="aovatalk_realtime_2026"     # LOCAL db only, bound to 127.0.0.1
DB_PORT="5432"
ASTERISK_MAJOR="20"                  # Asterisk 20 LTS
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Web UI (portal) ──────────────────────────────────────────────────────────
# A client's FIRST server hosts the management web UI; extra gateway servers in
# the same client deployment run WITH_PORTAL=0 (telephony only). Default on.
WITH_PORTAL="${WITH_PORTAL:-1}"
PORTAL_PORT="${PORTAL_PORT:-80}"
PORTAL_DIR="/opt/astgw"
PORTAL_BUNDLE="${PORTAL_BUNDLE:-$SCRIPT_DIR/portal-bundle.tar.gz}"  # built by build-portal-bundle.sh
NODE_VER="${NODE_VER:-v20.18.1}"     # EL7 needs the unofficial glibc-217 build

log(){ echo "[$(date '+%F %T')] $*"; }
die(){ echo "[$(date '+%F %T')] FATAL: $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "must run as root"

# ── Detect OS family ─────────────────────────────────────────────────────────
. /etc/os-release
case "${ID:-}" in
  centos|rhel|rocky|almalinux|fedora) OS_FAMILY="rhel" ;;
  debian|ubuntu)                      OS_FAMILY="debian" ;;
  *) die "Unsupported OS: ${ID:-unknown}" ;;
esac
log "OS: ${PRETTY_NAME:-$ID}  ->  family=$OS_FAMILY"

# ── Phase 1: hostname ────────────────────────────────────────────────────────
log "Phase 1: hostname -> $FQDN"
hostnamectl set-hostname "$FQDN" 2>/dev/null || hostname "$FQDN"
grep -q "$FQDN" /etc/hosts || echo "127.0.0.1 $FQDN ${FQDN%%.*}" >> /etc/hosts

# ── Phase 2: packages + toolchain ────────────────────────────────────────────
log "Phase 2: installing packages"
GCC_PREFIX=""
if [ "$OS_FAMILY" = rhel ]; then
    RHEL_MAJOR="$(rpm -E %{rhel} 2>/dev/null || echo 7)"
    yum -y install epel-release 2>/dev/null || true
    yum -y install wget tar patch bzip2 make gcc gcc-c++ \
        libedit-devel libuuid-devel libxml2-devel sqlite-devel openssl-devel \
        ncurses-devel postgresql-server postgresql-contrib postgresql-devel \
        python3 python3-pip || die "yum package install failed"
    # Asterisk 20 needs a newer compiler than RHEL/CentOS 7 ships (gcc 4.8).
    if [ "$RHEL_MAJOR" = 7 ]; then
        yum -y install centos-release-scl 2>/dev/null || true
        yum -y install devtoolset-11 2>/dev/null || yum -y install devtoolset-9 2>/dev/null || true
        if   [ -f /opt/rh/devtoolset-11/enable ]; then GCC_PREFIX="source /opt/rh/devtoolset-11/enable;"
        elif [ -f /opt/rh/devtoolset-9/enable  ]; then GCC_PREFIX="source /opt/rh/devtoolset-9/enable;"
        fi
        log "toolchain: ${GCC_PREFIX:-system gcc}"
    fi
    PGDATA_DIR="/var/lib/pgsql/data"
    PG_SERVICE="postgresql"
else
    export DEBIAN_FRONTEND=noninteractive
    apt-get update || die "apt update failed"
    apt-get install -y build-essential wget tar patch \
        libedit-dev uuid-dev libxml2-dev libsqlite3-dev libssl-dev libncurses-dev \
        postgresql postgresql-contrib libpq-dev python3 python3-pip || die "apt install failed"
    PGDATA_DIR=""          # Debian auto-initialises its cluster
    PG_SERVICE="postgresql"
fi

pip3 install pyst2 websocket-client 2>/dev/null \
  || pip3 install --break-system-packages pyst2 websocket-client 2>/dev/null || true

# ── Phase 3: local PostgreSQL ────────────────────────────────────────────────
log "Phase 3: local PostgreSQL"
if [ "$OS_FAMILY" = rhel ]; then
    if [ ! -f "$PGDATA_DIR/PG_VERSION" ]; then
        postgresql-setup initdb 2>/dev/null || /usr/bin/postgresql-setup initdb || die "initdb failed"
    fi
    HBA="$PGDATA_DIR/pg_hba.conf"
    # allow password auth from localhost for the realtime user
    sed -i -E 's@^(host\s+all\s+all\s+127\.0\.0\.1/32\s+).*@\1md5@' "$HBA" 2>/dev/null || true
    grep -qE '127\.0\.0\.1/32\s+md5' "$HBA" || echo "host all all 127.0.0.1/32 md5" >> "$HBA"
    systemctl enable "$PG_SERVICE"; systemctl restart "$PG_SERVICE"
else
    systemctl enable "$PG_SERVICE"; systemctl restart "$PG_SERVICE"
fi

# role + database (idempotent)
su - postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'\"" | grep -q 1 \
  || su - postgres -c "psql -c \"CREATE ROLE $DB_USER LOGIN PASSWORD '$DB_PASS';\""
su - postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='$DB_NAME'\"" | grep -q 1 \
  || su - postgres -c "psql -c \"CREATE DATABASE $DB_NAME OWNER $DB_USER;\""

PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
  -f "$SCRIPT_DIR/aovatalk-schema.sql" || die "schema load failed"
log "DB ready: $DB_NAME @127.0.0.1 (user $DB_USER)"

# ── Phase 4: compile Asterisk ────────────────────────────────────────────────
log "Phase 4: compiling Asterisk $ASTERISK_MAJOR (this is the long part)"
systemctl stop asterisk 2>/dev/null || service asterisk stop 2>/dev/null || true
cd /usr/src
if ! ls -d asterisk-${ASTERISK_MAJOR}.*/ >/dev/null 2>&1; then
    wget -q "https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-${ASTERISK_MAJOR}-current.tar.gz" \
      || die "download failed"
    tar xzf asterisk-${ASTERISK_MAJOR}-current.tar.gz
fi
cd "$(ls -d /usr/src/asterisk-${ASTERISK_MAJOR}.*/ | head -1)" || die "source dir missing"

contrib/scripts/install_prereq install 2>/dev/null || true
bash -c "${GCC_PREFIX} ./configure --with-pjproject-bundled --with-jansson-bundled" || die "configure failed"
make menuselect.makeopts
menuselect/menuselect \
    --enable res_config_pgsql \
    --enable res_pjsip \
    --enable res_pjsip_endpoint_identifier_ip \
    --enable app_amd \
    menuselect.makeopts
bash -c "${GCC_PREFIX} make -j$(nproc)" || die "make failed"
make install
make samples
make config
ldconfig

# verify the PostgreSQL realtime backend actually built
ls /usr/lib*/asterisk/modules/res_config_pgsql.so >/dev/null 2>&1 \
  || die "res_config_pgsql.so not built — PostgreSQL realtime would not work"

# ── Phase 5: Asterisk configuration ──────────────────────────────────────────
log "Phase 5: writing Asterisk config"
sed -i 's/;maxfiles = 1000/maxfiles = 65536/' /etc/asterisk/asterisk.conf 2>/dev/null || true

cat > /etc/asterisk/res_pgsql.conf <<EOF
[general]
dbhost=127.0.0.1
dbport=$DB_PORT
dbname=$DB_NAME
dbuser=$DB_USER
dbpass=$DB_PASS
dbappname=asterisk
requirements=warn
EOF

cat > /etc/asterisk/extconfig.conf <<'EOF'
[settings]
ps_endpoints => pgsql,general,ps_endpoints
ps_aors => pgsql,general,ps_aors
ps_endpoint_id_ips => pgsql,general,ps_endpoint_id_ips
EOF

cat > /etc/asterisk/sorcery.conf <<'EOF'
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
EOF

cp "$SCRIPT_DIR/pjsip.conf"      /etc/asterisk/pjsip.conf
cp "$SCRIPT_DIR/extensions.conf" /etc/asterisk/extensions.conf

# Upstream switch placeholder — set the real carrier/switch IP, then `pjsip reload`.
# The dialplan dials PJSIP/...@voip-switch, so this endpoint must exist to route calls.
cat >> /etc/asterisk/pjsip.conf <<'EOF'

;=== UPSTREAM SWITCH (fill in before routing live traffic) ====================
;[voip-switch]
;type=endpoint
;transport=transport-udp
;context=from-clients
;disallow=all
;allow=ulaw,alaw
;aors=voip-switch
;
;[voip-switch]
;type=aor
;contact=sip:CHANGE_ME_SWITCH_IP:5060
;
;[voip-switch]
;type=identify
;endpoint=voip-switch
;match=CHANGE_ME_SWITCH_IP
;============================================================================
EOF

cat > /etc/asterisk/amd.conf <<'EOF'
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
EOF

cat > /etc/asterisk/logger.conf <<'EOF'
[general]
dateformat=%F %T.%3q

[logfiles]
console => notice,warning,error
messages => notice,warning,error
EOF

# autoload, but keep the deprecated chan_sip off so it can't fight PJSIP for 5060
cat > /etc/asterisk/modules.conf <<'EOF'
[modules]
autoload=yes
noload => chan_sip.so
EOF

# ── Phase 6: AMD AGI script ──────────────────────────────────────────────────
log "Phase 6: AMD AGI script"
mkdir -p /var/lib/asterisk/agi-bin /var/log/amd
cp "$SCRIPT_DIR/amd.py" /var/lib/asterisk/agi-bin/amd.py
chmod +x /var/lib/asterisk/agi-bin/amd.py
python3 -m py_compile /var/lib/asterisk/agi-bin/amd.py || log "WARN: amd.py did not byte-compile"

# ── Phase 7: firewall ────────────────────────────────────────────────────────
log "Phase 7: firewall"
if [ "$OS_FAMILY" = rhel ] && command -v firewall-cmd >/dev/null 2>&1; then
    systemctl enable firewalld; systemctl start firewalld
    firewall-cmd --permanent --add-service=ssh            # never lock out SSH
    firewall-cmd --permanent --add-port=5060/udp          # SIP
    firewall-cmd --permanent --add-port=10000-20000/udp   # RTP
    firewall-cmd --reload
    firewall-cmd --list-all || true
else
    # Debian / iptables fallback — append (do NOT flush) so SSH survives
    iptables -C INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    iptables -A INPUT -p udp --dport 5060 -j ACCEPT -m comment --comment 'AstGW: SIP'
    iptables -A INPUT -p udp --dport 10000:20000 -j ACCEPT -m comment --comment 'AstGW: RTP'
    mkdir -p /etc/iptables && iptables-save > /etc/iptables/rules.v4
fi

# ── Phase 8: start + verify ──────────────────────────────────────────────────
log "Phase 8: starting Asterisk"
systemctl daemon-reload 2>/dev/null || true
systemctl enable asterisk 2>/dev/null || true
systemctl restart asterisk 2>/dev/null || { service asterisk restart || /usr/sbin/asterisk; }
sleep 4

# ── Phase 9: web UI (first server only) ──────────────────────────────────────
if [ "$WITH_PORTAL" = 1 ]; then
  if [ ! -f "$PORTAL_BUNDLE" ]; then
    log "WARN: WITH_PORTAL=1 but $PORTAL_BUNDLE not found — skipping web UI."
    log "      Build it first:  bash build-portal-bundle.sh   (needs Node 20+/22)"
  else
    log "Phase 9: installing portal web UI on :$PORTAL_PORT (this is the client's first server)"

    # Node runtime — EL7's old glibc needs the unofficial glibc-217 build.
    if [ ! -x /usr/local/bin/node ]; then
      if [ "$OS_FAMILY" = rhel ] && [ "${RHEL_MAJOR:-}" = 7 ]; then
        NODE_URL="https://unofficial-builds.nodejs.org/download/release/${NODE_VER}/node-${NODE_VER}-linux-x64-glibc-217.tar.gz"
      else
        NODE_URL="https://nodejs.org/dist/${NODE_VER}/node-${NODE_VER}-linux-x64.tar.gz"
      fi
      wget -q "$NODE_URL" -O /tmp/node.tar.gz || die "Node download failed: $NODE_URL"
      rm -rf /usr/local/node && mkdir -p /usr/local/node
      tar xzf /tmp/node.tar.gz -C /usr/local/node --strip-components=1
      ln -sf /usr/local/node/bin/node /usr/local/bin/node
      ln -sf /usr/local/node/bin/npm  /usr/local/bin/npm
    fi
    /usr/local/bin/node -v >/dev/null 2>&1 || die "Node runtime won't run on this host"

    # Deploy the prebuilt bundle (build/ + package.json + prod node_modules)
    mkdir -p "$PORTAL_DIR"
    tar xzf "$PORTAL_BUNDLE" -C "$PORTAL_DIR"

    # Self-SSH key so the portal can manage this host's firewall (ssh.ts reads it)
    if [ ! -f /root/.ssh/astgw-portal.key ]; then
      ssh-keygen -t ed25519 -f /root/.ssh/astgw-portal.key -N '' -C astgw-portal >/dev/null
      cat /root/.ssh/astgw-portal.key.pub >> /root/.ssh/authorized_keys
      chmod 600 /root/.ssh/authorized_keys
    fi

    # systemd unit — DB creds passed via env (db.ts is env-driven)
    cat > /etc/systemd/system/astgw-portal.service <<UNIT
[Unit]
Description=AstGW Portal ($NODE_NAME)
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
WorkingDirectory=$PORTAL_DIR
Environment=NODE_ENV=production
Environment=PORT=$PORTAL_PORT
Environment=HOST=0.0.0.0
Environment=ORIGIN=http://$FQDN
Environment=PGHOST=127.0.0.1
Environment=PGPORT=$DB_PORT
Environment=PGDATABASE=$DB_NAME
Environment=PGUSER=$DB_USER
Environment=PGPASSWORD=$DB_PASS
ExecStart=/usr/local/bin/node $PORTAL_DIR/build/index.js
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
UNIT

    systemctl daemon-reload
    systemctl enable astgw-portal >/dev/null 2>&1
    systemctl restart astgw-portal

    # Open HTTP
    if [ "$OS_FAMILY" = rhel ] && command -v firewall-cmd >/dev/null 2>&1; then
      firewall-cmd --permanent --add-service=http >/dev/null 2>&1 || \
        firewall-cmd --permanent --add-port=${PORTAL_PORT}/tcp >/dev/null
      firewall-cmd --reload >/dev/null
    else
      iptables -C INPUT -p tcp --dport ${PORTAL_PORT} -j ACCEPT 2>/dev/null || \
        iptables -A INPUT -p tcp --dport ${PORTAL_PORT} -j ACCEPT
      iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
    sleep 3
    if [ "$(systemctl is-active astgw-portal)" = active ]; then
      log "Portal UP: http://$FQDN/   (first login admin/admin — CHANGE IT)"
    else
      log "WARN: portal service not active — check: journalctl -u astgw-portal"
    fi
  fi
else
  log "Phase 9: WITH_PORTAL=0 — gateway-only server, no web UI."
fi

echo "------------------------------------------------------------"
echo " VERIFY"
echo "------------------------------------------------------------"
asterisk -rx 'core show version'            2>/dev/null || true
asterisk -rx 'module show like res_config_pgsql' 2>/dev/null || true
asterisk -rx 'module show like res_pjsip'   2>/dev/null | tail -3 || true
asterisk -rx 'pjsip show endpoints'         2>/dev/null | tail -5 || true
echo "------------------------------------------------------------"
log "DONE: $NODE_NAME ($FQDN) on $NODE_IP — standalone node installed."
[ "$WITH_PORTAL" = 1 ] && echo "  Web UI:  http://$FQDN/   (login admin/admin — change it)"
echo "Next steps (need carrier/customer info you haven't provided yet):"
echo "  1. Add upstream gateway(s) in the portal (or fill [voip-switch] in pjsip.conf), then: pjsip reload"
echo "  2. Add the customer in the portal (/clients/new) — creates the realtime endpoint + firewall rule."

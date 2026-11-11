#!/bin/bash
###############################################################################
# AstGW STANDALONE node installer  (self-contained, OS-aware)
#
# Unlike install-server.sh (which joins a node to the shared portal DB on
# 5.9.21.179), this script makes ONE host fully self-contained:
#   - local PostgreSQL on 127.0.0.1 holding its own realtime + registry schema
#   - Asterisk (PJSIP realtime) compiled from source
#   - AMD_WS native module (app_amd_ws, from the pinned AMDY installer),
#     AMD + gateway-select AGI scripts, log rotation
#   - firewall baseline (SIP 5060 closed; the portal opens it per client IP)
#   - optional web portal (first server of a client deployment)
# Nothing here talks to any other AstGW host.
#
# Run AS ROOT, ON the target host, from a directory that holds this script and
# its files (standalone-schema.sql, migrations/, pjsip.conf, extensions.conf,
# extensions_gwtest.conf, logger.conf, logrotate-asterisk,
# cron-hourly-asterisk-logrotate, amd.py, gateway_select.py,
# portal-bundle.tar.gz):
#
#   bash install-standalone.sh nodes/<node>.env
#
# The node file sets NODE_NAME, FQDN, NODE_IP, DB_PASS and optionally
# ASTERISK_MAJOR (default 20), WITH_PORTAL (default 1), PORTAL_PORT (default 80),
# AMD_WS_INSTALLER_URL (default: the pinned v2.0.3 release installer; a file
# app_amd_ws-install.sh next to this script is used first, for offline installs).
# Re-running is safe: every phase is idempotent.
###############################################################################
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

log(){ echo "[$(date '+%F %T')] $*"; }
die(){ echo "[$(date '+%F %T')] FATAL: $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "must run as root"
NODE_FILE="${1:-}"
[ -n "$NODE_FILE" ] && [ -f "$NODE_FILE" ] || die "usage: $0 nodes/<node>.env"
# shellcheck disable=SC1090
. "$NODE_FILE"

# ── Per-node config ──────────────────────────────────────────────────────────
: "${NODE_NAME:?NODE_NAME missing in $NODE_FILE}"
: "${FQDN:?FQDN missing in $NODE_FILE}"
: "${NODE_IP:?NODE_IP missing in $NODE_FILE}"
: "${DB_PASS:?DB_PASS missing in $NODE_FILE}"
DB_NAME="${DB_NAME:-asterisk_mgmt}"
DB_USER="${DB_USER:-asterisk}"
DB_PORT="${DB_PORT:-5432}"
ASTERISK_MAJOR="${ASTERISK_MAJOR:-20}"
PG_MAJOR="${PG_MAJOR:-15}"          # EL7 only: PGDG build (distro 9.2 lacks ON CONFLICT)
RTP_START="${RTP_START:-10000}"
RTP_END="${RTP_END:-20000}"

# ── Web UI (portal) ──────────────────────────────────────────────────────────
# A client's FIRST server hosts the management web UI; extra gateway servers in
# the same client deployment run WITH_PORTAL=0 (telephony only). Default on.
WITH_PORTAL="${WITH_PORTAL:-1}"
PORTAL_PORT="${PORTAL_PORT:-80}"
PORTAL_DIR="/opt/astgw"
PORTAL_BUNDLE="${PORTAL_BUNDLE:-$SCRIPT_DIR/portal-bundle.tar.gz}"  # built by build-portal-bundle.sh
NODE_VER="${NODE_VER:-v20.18.1}"     # EL7 needs the unofficial glibc-217 build
AMD_WS_INSTALLER_URL="${AMD_WS_INSTALLER_URL:-https://raw.githubusercontent.com/nikvb/amd/v2.0.3/install.sh}"

for f in standalone-schema.sql pjsip.conf extensions.conf extensions_gwtest.conf \
         logger.conf logrotate-asterisk cron-hourly-asterisk-logrotate amd.py \
         gateway_select.py; do
  [ -f "$SCRIPT_DIR/$f" ] || die "missing $SCRIPT_DIR/$f"
done
ls "$SCRIPT_DIR"/migrations/*.sql >/dev/null 2>&1 || die "missing $SCRIPT_DIR/migrations/*.sql"

# ── Detect OS family ─────────────────────────────────────────────────────────
. /etc/os-release
case "${ID:-}" in
  centos|rhel|rocky|almalinux|fedora) OS_FAMILY="rhel" ;;
  debian|ubuntu)                      OS_FAMILY="debian" ;;
  *) die "Unsupported OS: ${ID:-unknown}" ;;
esac
RHEL_MAJOR=""
[ "$OS_FAMILY" = rhel ] && RHEL_MAJOR="$(rpm -E %{rhel} 2>/dev/null || echo 7)"
log "Node $NODE_NAME ($FQDN, $NODE_IP) — OS: ${PRETTY_NAME:-$ID} -> family=$OS_FAMILY ${RHEL_MAJOR}"

# ── Phase 1: hostname ────────────────────────────────────────────────────────
log "Phase 1: hostname -> $FQDN"
hostnamectl set-hostname "$FQDN" 2>/dev/null || hostname "$FQDN"
grep -q "$FQDN" /etc/hosts || echo "$NODE_IP $FQDN ${FQDN%%.*}" >> /etc/hosts

# ── Phase 2: packages + toolchain ────────────────────────────────────────────
log "Phase 2: installing packages"
GCC_PREFIX=""
PG_CONFIG_DIR=""
if [ "$OS_FAMILY" = rhel ]; then
    if [ "$RHEL_MAJOR" = 7 ]; then
        # CentOS 7 is EOL: mirror.centos.org is gone, everything lives on vault.
        yum -y install centos-release-scl || die "centos-release-scl install failed"
        for r in /etc/yum.repos.d/CentOS-SCLo-*.repo; do
            [ -f "$r" ] || continue
            sed -i -e 's/^mirrorlist=/#mirrorlist=/' \
                   -e 's|^#\s*baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|' \
                   -e 's|^baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|' "$r"
        done

        # EPEL 7 (archived): PGDG's EL7 packages need libzstd and llvm5.0-devel from it.
        yum -y install epel-release || die "epel-release install failed"
        sed -i -e 's/^metalink=/#metalink=/' -e 's/^mirrorlist=/#mirrorlist=/' \
               -e 's|^#\?\s*baseurl=.*/pub/epel/7/\$basearch|baseurl=https://archives.fedoraproject.org/pub/archive/epel/7/$basearch|' \
               /etc/yum.repos.d/epel.repo
        # epel-testing / debuginfo / source sections stay disabled (default)

        # PostgreSQL from PGDG (frozen EL7 repo). Only the one major we need is
        # enabled: other majors on that repo return 404/410 and break yum.
        if ! rpm -q pgdg-redhat-repo >/dev/null 2>&1; then
            yum -y install "https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm" \
              || die "PGDG repo install failed"
        fi
        PGREPO=/etc/yum.repos.d/pgdg-redhat-all.repo
        sed -i 's/^enabled=1/enabled=0/' "$PGREPO"
        awk -v want="[pgdg${PG_MAJOR}]" '
            /^\[/ { sec=$0 }
            /^enabled=/ && sec==want { print "enabled=1"; next }
            { print }' "$PGREPO" > "$PGREPO.new" && mv "$PGREPO.new" "$PGREPO"

        yum -y install wget tar patch bzip2 make gcc gcc-c++ openssl \
            libedit-devel libuuid-devel libxml2-devel sqlite-devel openssl-devel \
            ncurses-devel python3 python3-pip \
            "postgresql${PG_MAJOR}" "postgresql${PG_MAJOR}-server" \
            "postgresql${PG_MAJOR}-contrib" "postgresql${PG_MAJOR}-devel" \
            || die "yum package install failed"
        # Asterisk 20 needs a newer compiler than CentOS 7 ships (gcc 4.8).
        yum -y install devtoolset-11-gcc devtoolset-11-gcc-c++ devtoolset-11-binutils \
            || die "devtoolset-11 install failed (SCL repo on vault?)"
        GCC_PREFIX="source /opt/rh/devtoolset-11/enable;"
        PG_CONFIG_DIR="/usr/pgsql-${PG_MAJOR}"
        PGDATA_DIR="/var/lib/pgsql/${PG_MAJOR}/data"
        PG_SERVICE="postgresql-${PG_MAJOR}"
        # psql on PATH for gateway_select.py (it runs plain `psql`)
        [ -x /usr/bin/psql ] || ln -sf "/usr/pgsql-${PG_MAJOR}/bin/psql" /usr/bin/psql
    else
        yum -y install epel-release 2>/dev/null || true
        yum -y install wget tar patch bzip2 make gcc gcc-c++ openssl \
            libedit-devel libuuid-devel libxml2-devel sqlite-devel openssl-devel \
            ncurses-devel postgresql-server postgresql-contrib postgresql-devel \
            python3 python3-pip || die "yum package install failed"
        PGDATA_DIR="/var/lib/pgsql/data"
        PG_SERVICE="postgresql"
    fi
else
    export DEBIAN_FRONTEND=noninteractive
    apt-get update || die "apt update failed"
    apt-get install -y build-essential wget tar patch openssl \
        libedit-dev uuid-dev libxml2-dev libsqlite3-dev libssl-dev libncurses-dev \
        postgresql postgresql-contrib libpq-dev python3 python3-pip iptables \
        || die "apt install failed"
    PGDATA_DIR=""          # Debian auto-initialises its cluster
    PG_SERVICE="postgresql"
fi

pip3 install pyst2 websocket-client 2>/dev/null \
  || pip3 install --break-system-packages pyst2 websocket-client 2>/dev/null \
  || die "pip install pyst2 websocket-client failed"
python3 -c 'import asterisk.agi, websocket' || die "python modules pyst2/websocket-client not importable"

# ── Phase 3: local PostgreSQL ────────────────────────────────────────────────
log "Phase 3: local PostgreSQL"
if [ "$OS_FAMILY" = rhel ]; then
    if [ ! -f "$PGDATA_DIR/PG_VERSION" ]; then
        if [ "$RHEL_MAJOR" = 7 ]; then
            "/usr/pgsql-${PG_MAJOR}/bin/postgresql-${PG_MAJOR}-setup" initdb || die "initdb failed"
        else
            postgresql-setup --initdb || postgresql-setup initdb || die "initdb failed"
        fi
    fi
    HBA="$PGDATA_DIR/pg_hba.conf"
    # password auth from localhost for the realtime user (keep scram-sha-256
    # if PG already uses it on that line; replace ident/trust with md5)
    grep -qE '^host\s+all\s+all\s+127\.0\.0\.1/32\s+(md5|scram-sha-256)' "$HBA" \
      || sed -i -E 's@^(host\s+all\s+all\s+127\.0\.0\.1/32\s+).*@\1md5@' "$HBA"
    grep -qE '^host\s+all\s+all\s+127\.0\.0\.1/32\s+(md5|scram-sha-256)' "$HBA" \
      || echo "host all all 127.0.0.1/32 md5" >> "$HBA"
fi
systemctl enable "$PG_SERVICE"; systemctl restart "$PG_SERVICE" || die "PostgreSQL start failed"
su - postgres -c "psql -tAc 'SHOW listen_addresses'" | grep -qx localhost \
  || log "WARN: PostgreSQL listen_addresses is not 'localhost' — check postgresql.conf"

# role + database (idempotent; password re-set so a re-run always matches the node file)
su - postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'\"" | grep -q 1 \
  || su - postgres -c "psql -c \"CREATE ROLE $DB_USER LOGIN;\""
su - postgres -c "psql -c \"ALTER ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';\"" >/dev/null
su - postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='$DB_NAME'\"" | grep -q 1 \
  || su - postgres -c "psql -c \"CREATE DATABASE $DB_NAME OWNER $DB_USER;\""

export PGPASSWORD="$DB_PASS"
PSQL=(psql -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME")
"${PSQL[@]}" -q -f "$SCRIPT_DIR/standalone-schema.sql" || die "schema load failed"
for m in "$SCRIPT_DIR"/migrations/*.sql; do
    log "  migration $(basename "$m")"
    "${PSQL[@]}" -q -f "$m" || die "migration $(basename "$m") failed"
done
"${PSQL[@]}" -q <<SQL || die "seed failed"
INSERT INTO servers (name, ip, status, enabled) VALUES ('$NODE_NAME', '$NODE_IP', 'active', true)
  ON CONFLICT (ip) DO UPDATE SET name = EXCLUDED.name, status = 'active', enabled = true;
INSERT INTO settings (key, value) VALUES ('sip_port', '5060') ON CONFLICT (key) DO NOTHING;
INSERT INTO settings (key, value) VALUES ('hostname', '$FQDN') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
SQL
unset PGPASSWORD
log "DB ready: $DB_NAME @127.0.0.1 (user $DB_USER)"

# ── Phase 4: compile Asterisk ────────────────────────────────────────────────
if [ -x /usr/sbin/asterisk ] && ls /usr/lib*/asterisk/modules/res_config_pgsql.so >/dev/null 2>&1 \
   && [ "${FORCE_REBUILD:-0}" != 1 ]; then
    log "Phase 4: Asterisk already installed ($(/usr/sbin/asterisk -V)) — skip (FORCE_REBUILD=1 to rebuild)"
else
    log "Phase 4: compiling Asterisk $ASTERISK_MAJOR (this is the long part)"
    systemctl stop asterisk 2>/dev/null || true
    cd /usr/src || die "no /usr/src"
    if ! ls -d asterisk-${ASTERISK_MAJOR}.*/ >/dev/null 2>&1; then
        wget -q "https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-${ASTERISK_MAJOR}-current.tar.gz" \
          || die "download failed"
        tar xzf asterisk-${ASTERISK_MAJOR}-current.tar.gz
    fi
    cd "$(ls -d /usr/src/asterisk-${ASTERISK_MAJOR}.*/ | head -1)" || die "source dir missing"

    CONF_OPTS="--with-pjproject-bundled --with-jansson-bundled"
    [ "$OS_FAMILY" = rhel ] && CONF_OPTS="$CONF_OPTS --libdir=/usr/lib64"
    [ -n "$PG_CONFIG_DIR" ] && CONF_OPTS="$CONF_OPTS --with-postgres=$PG_CONFIG_DIR"
    # install_prereq is skipped on EL7: it pulls EPEL, whose EL7 mirrors are gone.
    [ "$RHEL_MAJOR" != 7 ] && { contrib/scripts/install_prereq install 2>/dev/null || true; }
    if [ "$RHEL_MAJOR" = 7 ]; then
        # devtoolset-11 on EL7: libasteriskpj.so is linked with gcc, so it gets no
        # libstdc++_nonshared and leaves `operator delete(void*, size_t)` (_ZdlPvm)
        # undefined; the final C++ link of `asterisk` then fails with
        # "local symbol _ZdlPvm ... is referenced by DSO". Link the DSO with
        # -lstdc++ too, so it carries its own private copy.
        grep -q 'CC_LIBS)  -lstdc++' main/Makefile \
          || sed -i 's|^\t$(CMD_PREFIX) $(CC) -o $@ $(CC_LDFLAGS_SO) $< $(CC_LIBS)$|&  -lstdc++|' main/Makefile
        grep -q 'CC_LIBS)  -lstdc++' main/Makefile || die "libasteriskpj link patch did not apply"
    fi
    bash -c "${GCC_PREFIX} ./configure $CONF_OPTS" || die "configure failed"
    make menuselect.makeopts
    menuselect/menuselect \
        --enable res_config_pgsql \
        --enable res_pjsip \
        --enable res_pjsip_endpoint_identifier_ip \
        --enable app_amd \
        menuselect.makeopts
    bash -c "${GCC_PREFIX} make -j$(nproc)" || die "make failed"
    bash -c "${GCC_PREFIX} make install" || die "make install failed"
    [ -f /etc/asterisk/asterisk.conf ] || make samples
    make config
    ldconfig
fi

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
chmod 640 /etc/asterisk/res_pgsql.conf

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

cp "$SCRIPT_DIR/pjsip.conf"             /etc/asterisk/pjsip.conf
cp "$SCRIPT_DIR/extensions.conf"        /etc/asterisk/extensions.conf
cp "$SCRIPT_DIR/extensions_gwtest.conf" /etc/asterisk/extensions_gwtest.conf
cp "$SCRIPT_DIR/logger.conf"            /etc/asterisk/logger.conf

# Portal gateways are PJSIP realtime rows (src/lib/gateways.ts), not file
# blocks. pjsip_gateways.conf stays only for hand-written static endpoints;
# keep an existing file and include it.
touch /etc/asterisk/pjsip_gateways.conf
grep -q 'pjsip_gateways.conf' /etc/asterisk/pjsip.conf \
  || printf '\n; Upstream gateways managed by the AstGW portal\n#tryinclude pjsip_gateways.conf\n' >> /etc/asterisk/pjsip.conf
# The default upstream (voip-switch) is a realtime endpoint: set it in the
# portal Settings page. Do not add a static [voip-switch] here.

cat > /etc/asterisk/rtp.conf <<EOF
[general]
rtpstart=$RTP_START
rtpend=$RTP_END
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

# AMD_WS native module ([amd-check] in extensions.conf). No ViciDial DB on a
# gateway: the dialplan passes the number with p(). connect_timeout_ms=3000
# gives up on an unreachable AMDY in 3 s (default 10 s).
cat > /etc/asterisk/amd_ws.conf <<'EOF'
[general]
host=api.amdy.io
port=2700
connect_timeout_ms=3000
db=no
trace=no
EOF

# autoload, but keep the deprecated chan_sip off so it can't fight PJSIP for 5060
cat > /etc/asterisk/modules.conf <<'EOF'
[modules]
autoload=yes
noload => chan_sip.so
EOF

# log rotation (full.log has grown to 60 GB without it)
cp "$SCRIPT_DIR/logrotate-asterisk"             /etc/logrotate.d/asterisk
cp "$SCRIPT_DIR/cron-hourly-asterisk-logrotate" /etc/cron.hourly/asterisk-logrotate
chmod 0644 /etc/logrotate.d/asterisk; chmod 0755 /etc/cron.hourly/asterisk-logrotate
logrotate -d /etc/logrotate.d/asterisk >/dev/null 2>&1 || log "WARN: logrotate config check failed"

# ── Phase 6: AGI scripts ─────────────────────────────────────────────────────
log "Phase 6: AGI scripts (amd.py, gateway_select.py)"
mkdir -p /var/lib/asterisk/agi-bin /var/log/amd
for a in amd.py gateway_select.py; do
    cp "$SCRIPT_DIR/$a" "/var/lib/asterisk/agi-bin/$a"
    chmod +x "/var/lib/asterisk/agi-bin/$a"
    python3 -m py_compile "/var/lib/asterisk/agi-bin/$a" || die "$a did not byte-compile"
done

# ── Phase 7: firewall ────────────────────────────────────────────────────────
# SIP 5060 is NOT opened to the world. The portal opens it for each client IP
# when the client is added (addFirewallRule). Replies from upstream gateways
# come back as ESTABLISHED traffic.
log "Phase 7: firewall"
if [ "$OS_FAMILY" = rhel ] && command -v firewall-cmd >/dev/null 2>&1; then
    systemctl enable firewalld; systemctl start firewalld
    firewall-cmd --permanent --add-service=ssh                       # never lock out SSH
    firewall-cmd --permanent --remove-port=5060/udp >/dev/null 2>&1 || true
    firewall-cmd --permanent --add-port=${RTP_START}-${RTP_END}/udp  # RTP
    [ "$WITH_PORTAL" = 1 ] && firewall-cmd --permanent --add-port=${PORTAL_PORT}/tcp
    firewall-cmd --reload
    firewall-cmd --list-all || true
else
    iptables -C INPUT -i lo -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -i lo -j ACCEPT
    iptables -C INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null \
      || iptables -I INPUT 2 -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -C INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    iptables -C INPUT -p udp --dport ${RTP_START}:${RTP_END} -j ACCEPT 2>/dev/null \
      || iptables -A INPUT -p udp --dport ${RTP_START}:${RTP_END} -j ACCEPT -m comment --comment 'AstGW: RTP'
    [ "$WITH_PORTAL" = 1 ] && { iptables -C INPUT -p tcp --dport ${PORTAL_PORT} -j ACCEPT 2>/dev/null \
      || iptables -A INPUT -p tcp --dport ${PORTAL_PORT} -j ACCEPT; }
    mkdir -p /etc/iptables && iptables-save > /etc/iptables/rules.v4
    log "WARN: iptables INPUT policy left unchanged — set it to DROP once you have checked the rules"
fi

# ── Phase 8: start Asterisk ──────────────────────────────────────────────────
log "Phase 8: starting Asterisk"
systemctl daemon-reload 2>/dev/null || true
systemctl enable asterisk 2>/dev/null || true
systemctl restart asterisk 2>/dev/null || { service asterisk restart || /usr/sbin/asterisk; }
sleep 5

# ── Phase 8b: AMD_WS native module ───────────────────────────────────────────
# [amd-check] calls AMD_WS(); without the module every answered call would hit
# an unknown application, so a failure here stops the install.
# Same as: curl -fsSL <AMD_WS_INSTALLER_URL> | bash -s -- -y
log "Phase 8b: AMD_WS module (app_amd_ws)"
AMDWS_INST="$SCRIPT_DIR/app_amd_ws-install.sh"
if [ ! -f "$AMDWS_INST" ]; then
    AMDWS_INST="$(mktemp /tmp/app_amd_ws-install.XXXXXX)"
    curl -fsSL --retry 3 "$AMD_WS_INSTALLER_URL" -o "$AMDWS_INST" \
      || die "download of the app_amd_ws installer failed ($AMD_WS_INSTALLER_URL)"
fi
# It finds the headers in the Asterisk source tree from Phase 4, builds,
# installs and loads the module.
bash "$AMDWS_INST" -y || die "app_amd_ws install failed (log: /var/log/app_amd_ws-install.log)"
/usr/sbin/asterisk -rx 'core show application AMD_WS' | grep AMD_WS >/dev/null \
  || die "AMD_WS application is not registered after the install"
log "AMD_WS: $(/usr/sbin/asterisk -rx 'module show like app_amd_ws' | grep app_amd_ws)"

# ── Phase 9: web UI (first server only) ──────────────────────────────────────
if [ "$WITH_PORTAL" = 1 ]; then
  [ -f "$PORTAL_BUNDLE" ] || die "WITH_PORTAL=1 but $PORTAL_BUNDLE not found — run build-portal-bundle.sh"
  log "Phase 9: installing portal web UI on :$PORTAL_PORT"

  # Node runtime — EL7's old glibc needs the unofficial glibc-217 build.
  if ! /usr/local/bin/node -v 2>/dev/null | grep -q "^${NODE_VER}$"; then
    if [ "$OS_FAMILY" = rhel ] && [ "$RHEL_MAJOR" = 7 ]; then
      NODE_URL="https://unofficial-builds.nodejs.org/download/release/${NODE_VER}/node-${NODE_VER}-linux-x64-glibc-217.tar.gz"
    else
      NODE_URL="https://nodejs.org/dist/${NODE_VER}/node-${NODE_VER}-linux-x64.tar.gz"
    fi
    wget -q "$NODE_URL" -O /tmp/node.tar.gz || die "Node download failed: $NODE_URL"
    rm -rf /usr/local/node && mkdir -p /usr/local/node
    tar xzf /tmp/node.tar.gz -C /usr/local/node --strip-components=1
    rm -f /tmp/node.tar.gz
    ln -sf /usr/local/node/bin/node /usr/local/bin/node
    ln -sf /usr/local/node/bin/npm  /usr/local/bin/npm
  fi
  /usr/local/bin/node -v >/dev/null 2>&1 || die "Node runtime won't run on this host"

  # Deploy the prebuilt bundle (build/ + package.json + prod node_modules)
  mkdir -p "$PORTAL_DIR"
  rm -rf "$PORTAL_DIR/build" "$PORTAL_DIR/node_modules"
  tar xzf "$PORTAL_BUNDLE" -C "$PORTAL_DIR" || die "bundle extract failed"

  # Self-SSH key so the portal can manage this host's firewall + gateways (ssh.ts)
  if [ ! -f /root/.ssh/astgw-portal.key ]; then
    mkdir -p /root/.ssh && chmod 700 /root/.ssh
    ssh-keygen -t ed25519 -f /root/.ssh/astgw-portal.key -N '' -C "astgw-portal@$NODE_NAME" >/dev/null
  fi
  grep -qF "$(cut -d' ' -f2 /root/.ssh/astgw-portal.key.pub)" /root/.ssh/authorized_keys 2>/dev/null \
    || cat /root/.ssh/astgw-portal.key.pub >> /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys

  # systemd unit — DB creds via env (db.ts is env-driven). PROTOCOL_HEADER and
  # HOST_HEADER let the portal answer on the IP and on the hostname (also behind
  # a proxy). PORTAL_API_URL is unset: no reporting to the external Portal API.
  cat > /etc/systemd/system/astgw-portal.service <<UNIT
[Unit]
Description=AstGW Portal ($NODE_NAME)
After=network.target $PG_SERVICE.service
Wants=$PG_SERVICE.service

[Service]
Type=simple
WorkingDirectory=$PORTAL_DIR
Environment=NODE_ENV=production
Environment=PORT=$PORTAL_PORT
Environment=HOST=0.0.0.0
Environment=PROTOCOL_HEADER=x-forwarded-proto
Environment=HOST_HEADER=host
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
  chmod 600 /etc/systemd/system/astgw-portal.service

  systemctl daemon-reload
  systemctl enable astgw-portal >/dev/null 2>&1
  systemctl restart astgw-portal
  sleep 3
  if [ "$(systemctl is-active astgw-portal)" = active ]; then
    log "Portal UP: http://$NODE_IP:$PORTAL_PORT/   (first login admin/admin — CHANGE IT)"
  else
    log "WARN: portal service not active — check: journalctl -u astgw-portal"
  fi
else
  log "Phase 9: WITH_PORTAL=0 — gateway-only server, no web UI."
fi

echo "------------------------------------------------------------"
echo " VERIFY"
echo "------------------------------------------------------------"
asterisk -rx 'core show version'                  2>/dev/null || true
asterisk -rx 'module show like res_config_pgsql'  2>/dev/null || true
asterisk -rx 'realtime show pgsql status'         2>/dev/null || true
asterisk -rx 'pjsip show transports'              2>/dev/null | tail -4 || true
asterisk -rx 'pjsip show endpoints'               2>/dev/null | tail -5 || true
echo "------------------------------------------------------------"
log "DONE: $NODE_NAME ($FQDN) on $NODE_IP — standalone node installed."
[ "$WITH_PORTAL" = 1 ] && echo "  Web UI:  http://$NODE_IP:$PORTAL_PORT/   (login admin/admin — change it)"
echo "Next steps (need carrier/customer info):"
echo "  1. Set the VOIP switch in Settings, or add upstream gateway(s) on the Gateways page."
echo "  2. Add the customer on /clients/new — creates the realtime endpoint + 5060 firewall rule."

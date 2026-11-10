-- AstGW standalone node schema (generic, any node).
-- Self-contained: this DB lives LOCALLY on the node, not in the shared portal DB.
-- Needs PostgreSQL 9.5+ (the portal uses INSERT ... ON CONFLICT).
-- Apply migrations/*.sql after this file. Node-specific seed rows are written
-- by install-standalone.sh.

-- ── PJSIP realtime tables (read by Asterisk res_config_pgsql) ────────────────
CREATE TABLE IF NOT EXISTS ps_endpoints (
    id              varchar(255) PRIMARY KEY,
    transport       varchar(64),
    aors            varchar(255),
    context         varchar(64)  DEFAULT 'from-clients',
    disallow        varchar(64)  DEFAULT 'all',
    allow           varchar(255) DEFAULT 'ulaw,alaw',
    direct_media    varchar(8)   DEFAULT 'no',
    rtp_symmetric   varchar(8)   DEFAULT 'yes',
    force_rport     varchar(8)   DEFAULT 'yes',
    rewrite_contact varchar(8)   DEFAULT 'yes',
    identify_by     varchar(64)  DEFAULT 'ip',
    set_var         varchar(255),
    mailboxes       varchar(255)   -- queried by Asterisk's MWI subsystem at startup
);

CREATE TABLE IF NOT EXISTS ps_aors (
    id              varchar(255) PRIMARY KEY,
    contact         varchar(255),  -- static contact (voip-switch, written by switch.ts)
    max_contacts    integer      DEFAULT 5
);

CREATE TABLE IF NOT EXISTS ps_endpoint_id_ips (
    -- switch.ts inserts (endpoint, match) without an id, so the id needs a default.
    id              varchar(255) PRIMARY KEY DEFAULT md5(random()::text || clock_timestamp()::text),
    endpoint        varchar(255),
    "match"         varchar(255)
);

-- ── Portal / registry tables ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS clients (
    id          serial PRIMARY KEY,
    name        varchar(255) NOT NULL,
    ip          varchar(64)  NOT NULL UNIQUE,
    tech_prefix varchar(64),
    enabled     boolean      DEFAULT true,
    created_at  timestamptz  DEFAULT now()
);

-- Upstream gateways (outbound peers); the portal writes their PJSIP config to
-- /etc/asterisk/pjsip_gateways.conf via addGatewayPjsip().
CREATE TABLE IF NOT EXISTS gateways (
    id          serial PRIMARY KEY,
    name        varchar(255) NOT NULL,
    ip          varchar(64)  NOT NULL UNIQUE,
    port        integer      DEFAULT 5060,
    weight      integer      DEFAULT 1,
    enabled     boolean      DEFAULT true,
    created_at  timestamptz  DEFAULT now()
);

CREATE TABLE IF NOT EXISTS servers (
    id      serial PRIMARY KEY,
    name    varchar(255) NOT NULL,
    ip      varchar(64)  NOT NULL UNIQUE,
    status  varchar(32)  DEFAULT 'active',
    enabled boolean      DEFAULT true
);

CREATE TABLE IF NOT EXISTS settings (
    key   varchar(128) PRIMARY KEY,
    value text
);

CREATE TABLE IF NOT EXISTS admin_users (
    id            serial PRIMARY KEY,
    username      varchar(128) NOT NULL UNIQUE,
    password_hash text         NOT NULL
);

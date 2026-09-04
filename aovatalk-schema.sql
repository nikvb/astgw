-- AstGW standalone node schema — aovatalk (sip.aovatalk.com)
-- Self-contained: this DB lives LOCALLY on the gateway host, not the shared portal DB.
-- Tables: PJSIP realtime (ps_*) + portal registry (clients/servers/settings/admin_users).

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
    max_contacts    integer      DEFAULT 5
);

CREATE TABLE IF NOT EXISTS ps_endpoint_id_ips (
    id              varchar(255) PRIMARY KEY,
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
-- each server's /etc/asterisk/pjsip_gateways.conf via addGatewayPjsip().
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

-- Register this host as its own (and only) server in its local registry.
INSERT INTO servers (name, ip, status, enabled)
VALUES ('aovatalk', '216.106.178.91', 'active', true)
ON CONFLICT (ip) DO NOTHING;

INSERT INTO settings (key, value) VALUES ('sip_port', '5060') ON CONFLICT (key) DO NOTHING;
INSERT INTO settings (key, value) VALUES ('hostname', 'sip.aovatalk.com') ON CONFLICT (key) DO NOTHING;

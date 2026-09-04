# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**AstGW Manager** — a SvelteKit web portal for managing Asterisk 22 gateway nodes. It provisions SIP clients into a shared PostgreSQL realtime database, manages iptables firewall rules on gateway servers via SSH, and automates new server installation.

The portal runs on the DB/portal host (`5.9.21.179`). Gateway servers are remote Debian 13 machines that connect to the shared PostgreSQL DB for PJSIP realtime configuration.

## Tech Stack

- **Frontend/Backend**: SvelteKit 5 (Svelte `$props()` runes syntax, server-side form actions)
- **Database**: PostgreSQL via `pg` (node-postgres), database `asterisk_mgmt`, user `asterisk`
- **Auth**: In-memory session map with bcrypt password hashing (`bcryptjs`)
- **SSH**: `ssh2` npm package, key at `/root/.ssh/astgw-portal.key` (fallback: `/root/.ssh/id_rsa`)
- **No package.json present** — this is a source files directory, not the full SvelteKit project root

## Key Architecture

### Database Tables
- `admin_users` — portal login credentials
- `clients` — client registry (name, ip, tech_prefix, enabled)
- `servers` — gateway server registry (name, ip, status, enabled)
- `settings` — key/value store (voip_switch_ip, sip_port)
- `ps_endpoints`, `ps_aors`, `ps_endpoint_id_ips` — Asterisk PJSIP realtime tables

### Client Provisioning Flow (`/clients/new`)
When a client is added:
1. Insert into `clients` table
2. Insert PJSIP realtime records (`ps_endpoints`, `ps_aors`, `ps_endpoint_id_ips`) using a slug derived from the client name (`name.toLowerCase().replace(/[^a-z0-9]+/g, "-")`)
3. SSH into every enabled server and run `iptables -I INPUT 68 -s <ip> -p udp --dport 5060 -j ACCEPT`

When a client is deleted, all three steps are reversed.

### Server Installation Flow (`/servers`)
Adding a server:
1. Inserts record with `status = 'installing'`
2. Spawns `install-server.sh <ip> <name>` as a detached background process
3. Logs output to `/var/log/astgw-install/<name>.log`
4. Script SSHes into the new server and: installs OS deps, compiles Asterisk 22 from source, writes config files, deploys AMD AGI script, sets up iptables baseline, syncs existing client rules, starts Asterisk, and opens PostgreSQL port on the DB host firewall

Install log viewable via `GET /servers/log?name=<server-name>`.

### Authentication
Session tokens are stored in-memory (lost on server restart). Default admin credentials are auto-created on first startup via `ensureAdmin()` in `hooks.server.ts` (username: `admin`, password: `admin`). All routes redirect to `/login` if no valid session.

### Asterisk Config Files
- `pjsip.conf` and `extensions.conf` in this directory are SCP'd to new servers during install
- AMD detection uses `amd.py` (AGI script) deployed to `/var/lib/asterisk/agi-bin/`
- `amd_detect.py` uses WebSocket to `ws://api.amdy.io:2700` for ML-based answering machine detection

### `$lib` Path Aliases
- `$lib/db` → `src/lib/db.ts` — PostgreSQL pool (hardcoded credentials)
- `$lib/auth` → `src/lib/auth.ts` — session management
- `$lib/ssh` → `src/lib/ssh.ts` — SSH execution and firewall rule helpers

## Files at Root (Not in `src/`)
- `install-server.sh` — full server provisioning script (run by portal, not on new server)
- `deploy_amdy.sh` — deploys AMD detection scripts to a server (run locally on the server)
- `pjsip.conf`, `extensions.conf` — Asterisk config templates SCP'd during install
- `amd.py` — AMD AGI script deployed to gateway servers
- `clients-new-page.svelte`, `settings-page.svelte`, `settings-page.server.ts`, `ssh.ts` — draft/staging files, not in active `src/` tree

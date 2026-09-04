#!/usr/bin/python3
"""
AstGW Gateway Load Balancer AGI Script
Queries the gateways table and picks one using weighted random selection.
Sets GATEWAY_ENDPOINT channel variable (PJSIP endpoint name) for use in dialplan.
"""
import sys
import os
import re
import random
import subprocess

# --- DB config (patched by install script) ---
DB_HOST = "127.0.0.1"
DB_PORT = "5432"
DB_NAME = "asterisk_mgmt"
DB_USER = "asterisk"
DB_PASS = "ast3r1sk_gw_2026"

# --- AGI helpers ---
def agi_read_env():
    while True:
        line = sys.stdin.readline().strip()
        if not line:
            break

def agi_set(key, value):
    sys.stdout.write('SET VARIABLE {} "{}"\n'.format(key, value))
    sys.stdout.flush()
    sys.stdin.readline()

def agi_verbose(msg):
    sys.stdout.write('VERBOSE "{}" 1\n'.format(msg.replace('"', "'")))
    sys.stdout.flush()
    sys.stdin.readline()

def name_to_slug(name):
    return "gateway-" + re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-')

# --- Main ---
agi_read_env()

try:
    result = subprocess.run(
        ["psql", "-h", DB_HOST, "-p", DB_PORT, "-U", DB_USER, "-d", DB_NAME,
         "-t", "-A", "-F", "\t",
         "-c", "SELECT name, weight FROM gateways WHERE enabled = true"],
        capture_output=True, text=True,
        env={**os.environ, "PGPASSWORD": DB_PASS}
    )

    rows = [line.strip() for line in result.stdout.strip().splitlines() if line.strip()]

    if not rows:
        agi_verbose("AstGW: No enabled gateways found")
        agi_set("GATEWAY_ENDPOINT", "")
        sys.exit(0)

    # Build weighted pool of endpoint slugs
    pool = []
    for row in rows:
        parts = row.split("\t")
        if len(parts) >= 2:
            name, weight = parts[0], int(parts[1])
            slug = name_to_slug(name)
            for _ in range(weight):
                pool.append(slug)

    if not pool:
        agi_set("GATEWAY_ENDPOINT", "")
        sys.exit(0)

    chosen = random.choice(pool)
    agi_verbose("AstGW: Selected gateway endpoint {}".format(chosen))
    agi_set("GATEWAY_ENDPOINT", chosen)

except Exception as e:
    agi_verbose("AstGW: Gateway selection error: {}".format(str(e)))
    agi_set("GATEWAY_ENDPOINT", "")

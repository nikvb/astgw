---
name: astgw-new-client
description: Use when adding, verifying or removing an AstGW SIP client (customer) - the portal form, the database rows and firewall rules it creates, the gateway assignment, the AMD reject status, and the checks that prove the client can place a call.
---

# Add a client to AstGW

A client is a customer that sends SIP traffic to the gateway servers. AstGW
accepts the traffic by source IP. There is no SIP registration and no password.

## Fleet

| Role | Host | Address |
|---|---|---|
| Portal and shared database | primo-amd01 | 5.9.21.179 |
| Gateway server | primo-amd02 | 167.235.7.108 |

- Portal: `https://primo-amd01.primodialler.cloud`
- Database: `asterisk_mgmt`, user `asterisk`, on primo-amd01 only.
- SSH: `ssh -i ~/.ssh/astgw-portal.key root@<server-ip>`

## 1. Collect the information

Ask the customer for these four items.

1. **Name** - the display name. The portal makes the PJSIP endpoint id from it:
   lower case, every run of non-alphanumeric characters becomes one `-`.
   `Acme Corp` becomes `acme-corp`.
2. **Source IP** - the one public IP the customer sends from. One row for each
   IP. The `clients.ip` column is unique, so a repeated IP is refused.
3. **Tech prefix** - the digits AstGW puts in front of the dialled number when
   it sends the call to the gateway.
4. **AMD reject status** - the SIP status the customer receives when AMD
   detects an answering machine. `603` Decline is the default. Choose `403`
   Forbidden only when the customer's dialer treats 603 as do-not-call.

Ask about gateways as well. A client with no gateway assigned uses the default
gateway. A client with gateways assigned uses only those gateways.

## 2. Add the client in the portal

1. Open `https://primo-amd01.primodialler.cloud` and log in.
2. Select **Add Client**.
3. Fill in the name, the IP, the tech prefix and the AMD reject status.
4. Select **Add Client**.

The form action does all of the following in one step. Do not do these by hand.

1. Inserts one row in `clients`.
2. Inserts the PJSIP realtime rows: `ps_endpoints` (context `from-clients`,
   codecs `ulaw,alaw`, `set_var` = `TECH_PREFIX=<prefix>`), `ps_aors`, and
   `ps_endpoint_id_ips` with the source IP.
3. Opens UDP 5060 for that IP on every enabled server, through firewalld or
   iptables.
4. Reports the IP to the external Portal API.

A firewall error or a Portal API error is a warning, not a failure. The client
row is still created. Read the warnings and fix the named server.

**Never put a second variable in `set_var`.** Asterisk realtime stores one
variable in that column. `set_var_handler()` splits the value at the first `=`
and keeps the rest as the value, so `TECH_PREFIX=777;AMD_REJECT=603` sets the
tech prefix to `777;AMD_REJECT=603` and breaks every call. Per-client values
other than the tech prefix belong in the `clients` table, and the AGI reads
them.

## 3. Assign gateways (optional)

1. Open the client page in the portal.
2. Use the **Gateways** card to assign one gateway or more.
3. Choose the mode:
   - **Weighted** - one gateway for each call, chosen by weight. Use it to
     share load.
   - **Failover** - the gateways in priority order. The dialplan tries the
     next one on `CHANUNAVAIL` or `CONGESTION`.

A client with gateways assigned never falls back to the default gateway and
never falls back to the switch.

## 4. Verify

Run every check. Do not report success before all of them pass.

1. Check the routing decision on **both** servers. This places no call.

   ```
   /var/lib/asterisk/agi-bin/gateway_select.py --test <client-ip>
   ```

   Read `GW_MODE`, `GW_COUNT`, `GW_1..N` and `__AMD_REJECT`. `GW_MODE=default`
   means the client has no assignment and uses the default gateway.

2. Check the endpoint exists on both servers.

   ```
   asterisk -rx 'pjsip show endpoint <slug>'
   ```

3. Check the source IP match on both servers.

   ```
   asterisk -rx 'pjsip show identifies' | grep <client-ip>
   ```

4. Check the firewall rule on both servers.

   ```
   iptables -L INPUT -v -n | grep <client-ip>
   firewall-cmd --list-rich-rules | grep <client-ip>
   ```

5. Check that traffic arrives, after the customer starts to send.

   ```
   grep "Call from <slug>" /var/log/asterisk/full.log | tail -5
   ```

## 5. Remove a client

Use the **Delete** button on the client page. It reverses all three steps: the
PJSIP realtime rows, the `clients` row and the firewall rules on every enabled
server. Do not delete rows by hand, because the firewall rules stay behind.

## Facts that explain the behaviour

- **Routing**: `[from-clients]` reads the source IP from
  `ps_endpoint_id_ips`, then goes to `[gw-route]`. `[gw-route]` calls
  `gateway_select.py`, which sets `GW_*` and `__AMD_REJECT` from the database.
- **AMD rejection**: the dialplan cannot choose a SIP status. It hangs up with
  a Q.850 cause, and `hangup_cause2sip()` in `channels/chan_pjsip.c` maps it.
  Cause 21 gives 403 Forbidden. Cause 16 has no entry, so chan_pjsip returns 0
  and `ast_sip_session_terminate()` uses its fallback, 603 Decline.
- **Where the code is**: the portal source is `/home/na/astgw-files` on the
  workstation and `/root/astgw` on primo-amd01. Rebuild with `npm run build`
  and restart with `pm2 restart astgw`.
- **New servers**: `install-server.sh` copies `extensions.conf` and
  `gateway_select.py`, so a new server inherits the current behaviour.

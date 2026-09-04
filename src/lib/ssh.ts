import { Client } from "ssh2";
import { readFileSync } from "fs";

const SSH_KEY_PATH = "/root/.ssh/astgw-portal.key";

export async function sshExec(host: string, command: string, port = 22): Promise<string> {
  return new Promise((resolve, reject) => {
    const conn = new Client();
    let output = "";
    conn.on("ready", () => {
      conn.exec(command, (err, stream) => {
        if (err) { conn.end(); return reject(err); }
        stream.on("data", (data: Buffer) => { output += data.toString(); });
        stream.stderr.on("data", (data: Buffer) => { output += data.toString(); });
        stream.on("close", () => { conn.end(); resolve(output.trim()); });
      });
    });
    conn.on("error", reject);
    let privateKey: string;
    try { privateKey = readFileSync(SSH_KEY_PATH, "utf-8"); }
    catch { privateKey = readFileSync("/root/.ssh/id_rsa", "utf-8"); }
    conn.connect({ host, port, username: "root", privateKey });
  });
}

export async function addFirewallRule(serverIp: string, clientIp: string, clientName: string): Promise<string> {
  const safe = clientName.replace(/[^a-zA-Z0-9_ -]/g, "");
  const cmd = `
    if systemctl is-active --quiet firewalld; then
      firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="${clientIp}" port port="5060" protocol="udp" accept' && firewall-cmd --reload
    else
      iptables -I INPUT 68 -s ${clientIp} -p udp --dport 5060 -j ACCEPT -m comment --comment "AstGW: ${safe}" && iptables-save > /etc/iptables/rules.v4
    fi
  `.trim();
  return sshExec(serverIp, cmd);
}

export async function removeFirewallRule(serverIp: string, clientIp: string): Promise<string> {
  const cmd = `
    if systemctl is-active --quiet firewalld; then
      firewall-cmd --permanent --remove-rich-rule='rule family="ipv4" source address="${clientIp}" port port="5060" protocol="udp" accept' && firewall-cmd --reload
    else
      iptables -D INPUT -s ${clientIp} -p udp --dport 5060 -j ACCEPT 2>/dev/null; iptables-save > /etc/iptables/rules.v4
    fi
  `.trim();
  return sshExec(serverIp, cmd);
}

export function gatewaySlug(name: string): string {
  return "gateway-" + name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "");
}

export async function addGatewayPjsip(serverIp: string, slug: string, gwIp: string, gwPort: number): Promise<string> {
  const block = [
    `[${slug}]`,
    `type=endpoint`,
    `transport=transport-udp`,
    `allow=ulaw,alaw`,
    `direct_media=no`,
    `rtp_symmetric=yes`,
    `force_rport=yes`,
    `rewrite_contact=yes`,
    ``,
    `[${slug}]`,
    `type=aor`,
    `contact=sip:${gwIp}:${gwPort}`,
    ``,
  ].join("\\n");
  const cmd = `printf '${block}\\n' >> /etc/asterisk/pjsip_gateways.conf && asterisk -rx 'pjsip reload'`;
  return sshExec(serverIp, cmd);
}

export async function removeGatewayPjsip(serverIp: string, slug: string): Promise<string> {
  const cmd = `python3 -c "
import re, sys
try:
    f = open('/etc/asterisk/pjsip_gateways.conf', 'r')
    content = f.read()
    f.close()
    content = re.sub(r'\\\\[${slug}\\\\][^\\\\[]*', '', content)
    f = open('/etc/asterisk/pjsip_gateways.conf', 'w')
    f.write(content)
    f.close()
except Exception as e:
    sys.stderr.write(str(e))
" && asterisk -rx 'pjsip reload'`;
  return sshExec(serverIp, cmd);
}

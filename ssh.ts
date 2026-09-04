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
  const cmd = `iptables -I INPUT 68 -s ${clientIp} -p udp --dport 5060 -j ACCEPT -m comment --comment "AstGW: ${safe}" && iptables-save > /etc/iptables/rules.v4`;
  return sshExec(serverIp, cmd);
}

export async function removeFirewallRule(serverIp: string, clientIp: string): Promise<string> {
  const cmd = `iptables -D INPUT -s ${clientIp} -p udp --dport 5060 -j ACCEPT 2>/dev/null; iptables-save > /etc/iptables/rules.v4`;
  return sshExec(serverIp, cmd);
}

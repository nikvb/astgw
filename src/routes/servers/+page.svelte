<script lang="ts">
  import type { ActionData } from "./$types";
  let { data, form }: { data: any; form: ActionData } = $props();

  let logContent = $state("");
  let logServer = $state("");
  let showLog = $state(false);

  async function viewLog(name: string) {
    logServer = name;
    logContent = "Loading...";
    showLog = true;
    try {
      const res = await fetch(`/servers/log?name=${encodeURIComponent(name)}`);
      logContent = res.ok ? await res.text() : `Error: ${res.statusText}`;
    } catch (e: any) {
      logContent = `Error: ${e.message}`;
    }
  }

  function statusColor(status: string): string {
    if (status === "online") return "#22c55e";
    if (status === "installing") return "#f59e0b";
    if (status === "failed") return "#ef4444";
    return "#64748b";
  }
</script>

<div style="max-width:700px;margin:0 auto;padding:1.5rem;">
  <div style="display:flex;align-items:center;gap:1rem;margin-bottom:1.5rem;">
    <a href="/" style="color:#60a5fa;text-decoration:none;">← Back</a>
    <h1 style="font-size:1.3rem;">Asterisk Servers</h1>
  </div>

  {#if form?.error}
    <div style="background:#991b1b;padding:0.5rem 1rem;border-radius:4px;margin-bottom:1rem;">{form.error}</div>
  {/if}

  <div style="background:#1e293b;border-radius:6px;overflow:hidden;margin-bottom:1.5rem;">
    <table style="width:100%;border-collapse:collapse;">
      <thead>
        <tr style="border-bottom:1px solid #334155;">
          <th style="text-align:left;padding:0.75rem;color:#94a3b8;font-size:0.85rem;">Name</th>
          <th style="text-align:left;padding:0.75rem;color:#94a3b8;font-size:0.85rem;">IP</th>
          <th style="text-align:center;padding:0.75rem;color:#94a3b8;font-size:0.85rem;">Status</th>
          <th style="text-align:right;padding:0.75rem;color:#94a3b8;font-size:0.85rem;">Actions</th>
        </tr>
      </thead>
      <tbody>
        {#each data.servers as server}
          <tr style="border-bottom:1px solid #1e293b;">
            <td style="padding:0.75rem;">{server.name}</td>
            <td style="padding:0.75rem;font-family:monospace;color:#93c5fd;">{server.ip}</td>
            <td style="padding:0.75rem;text-align:center;">
              <span style="display:inline-block;padding:0.15rem 0.5rem;border-radius:9999px;font-size:0.75rem;background:{statusColor(server.status)}22;color:{statusColor(server.status)};border:1px solid {statusColor(server.status)}44;">
                {server.status || "unknown"}
              </span>
            </td>
            <td style="padding:0.75rem;text-align:right;white-space:nowrap;">
              {#if server.status === "installing" || server.status === "failed"}
                <button onclick={() => viewLog(server.name)}
                  style="padding:0.25rem 0.75rem;background:#475569;color:white;border:none;border-radius:4px;cursor:pointer;font-size:0.8rem;margin-right:0.5rem;">Log</button>
              {/if}
              <form method="POST" action="?/delete" style="display:inline;">
                <input type="hidden" name="id" value={server.id} />
                <button type="submit" style="padding:0.25rem 0.75rem;background:#dc2626;color:white;border:none;border-radius:4px;cursor:pointer;font-size:0.8rem;">Remove</button>
              </form>
            </td>
          </tr>
        {:else}
          <tr><td colspan="4" style="padding:2rem;text-align:center;color:#64748b;">No servers configured.</td></tr>
        {/each}
      </tbody>
    </table>
  </div>

  <form method="POST" action="?/add" style="background:#1e293b;padding:1.5rem;border-radius:6px;">
    <h2 style="font-size:1rem;margin-bottom:1rem;">Add Server</h2>
    <div style="display:flex;gap:0.75rem;">
      <input name="name" placeholder="Server name" required
        style="flex:1;padding:0.5rem;background:#334155;border:1px solid #475569;border-radius:4px;color:#e2e8f0;" />
      <input name="ip" placeholder="IP address" required
        style="flex:1;padding:0.5rem;background:#334155;border:1px solid #475569;border-radius:4px;color:#e2e8f0;" />
      <button type="submit"
        style="padding:0.5rem 1rem;background:#2563eb;color:white;border:none;border-radius:4px;cursor:pointer;">Add</button>
    </div>
  </form>
</div>

{#if showLog}
  <div style="position:fixed;inset:0;background:rgba(0,0,0,0.7);display:flex;align-items:center;justify-content:center;z-index:50;"
    onclick={() => showLog = false} role="dialog">
    <div style="background:#0f172a;border:1px solid #334155;border-radius:8px;width:90%;max-width:800px;max-height:80vh;display:flex;flex-direction:column;"
      onclick={(e) => e.stopPropagation()} role="document">
      <div style="display:flex;justify-content:space-between;align-items:center;padding:1rem;border-bottom:1px solid #334155;">
        <h3 style="margin:0;font-size:1rem;">Install Log: {logServer}</h3>
        <div style="display:flex;gap:0.5rem;">
          <button onclick={() => viewLog(logServer)} style="padding:0.25rem 0.75rem;background:#475569;color:white;border:none;border-radius:4px;cursor:pointer;font-size:0.8rem;">Refresh</button>
          <button onclick={() => showLog = false} style="padding:0.25rem 0.75rem;background:#dc2626;color:white;border:none;border-radius:4px;cursor:pointer;font-size:0.8rem;">Close</button>
        </div>
      </div>
      <pre style="margin:0;padding:1rem;overflow:auto;flex:1;font-size:0.8rem;color:#cbd5e1;white-space:pre-wrap;word-break:break-all;">{logContent}</pre>
    </div>
  </div>
{/if}

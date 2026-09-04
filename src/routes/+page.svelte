<script lang="ts">
  let { data } = $props();
</script>

<div style="max-width:1100px;margin:0 auto;padding:1.5rem;">
  <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:1.5rem;">
    <h1 style="font-size:1.5rem;">AstGW Manager</h1>
    <div style="display:flex;gap:0.75rem;">
      <a href="/clients/new" style="padding:0.4rem 1rem;background:#16a34a;color:white;border-radius:4px;text-decoration:none;font-size:0.9rem;">+ Add Client</a>
      <a href="/gateways" style="padding:0.4rem 1rem;background:#475569;color:white;border-radius:4px;text-decoration:none;font-size:0.9rem;">Gateways</a>
      <a href="/servers" style="padding:0.4rem 1rem;background:#475569;color:white;border-radius:4px;text-decoration:none;font-size:0.9rem;">Servers</a>
      <a href="/settings" style="padding:0.4rem 1rem;background:#475569;color:white;border-radius:4px;text-decoration:none;font-size:0.9rem;">Settings</a>
      <form method="POST" action="?/logout" style="display:inline;">
        <button type="submit" style="padding:0.4rem 1rem;background:#dc2626;color:white;border:none;border-radius:4px;cursor:pointer;font-size:0.9rem;">Logout</button>
      </form>
    </div>
  </div>

  <div style="display:flex;gap:0.5rem;margin-bottom:1.5rem;">
    <div style="background:#1e293b;padding:1rem 1.5rem;border-radius:6px;flex:1;text-align:center;">
      <div style="font-size:2rem;font-weight:bold;">{data.clients.length}</div>
      <div style="color:#94a3b8;font-size:0.85rem;">Clients</div>
    </div>
    <div style="background:#1e293b;padding:1rem 1.5rem;border-radius:6px;flex:1;text-align:center;">
      <div style="font-size:2rem;font-weight:bold;">{data.servers.length}</div>
      <div style="color:#94a3b8;font-size:0.85rem;">Servers</div>
    </div>
    <div style="background:#1e293b;padding:1rem 1.5rem;border-radius:6px;flex:1;text-align:center;">
      <div style="font-size:2rem;font-weight:bold;">{data.clients.filter((c: any) => c.enabled).length}</div>
      <div style="color:#94a3b8;font-size:0.85rem;">Active</div>
    </div>
  </div>

  <div style="background:#1e293b;border-radius:6px;overflow:hidden;">
    <table style="width:100%;border-collapse:collapse;">
      <thead>
        <tr style="border-bottom:1px solid #334155;">
          <th style="text-align:left;padding:0.75rem;color:#94a3b8;font-size:0.85rem;">Name</th>
          <th style="text-align:left;padding:0.75rem;color:#94a3b8;font-size:0.85rem;">IP</th>
          <th style="text-align:left;padding:0.75rem;color:#94a3b8;font-size:0.85rem;">Tech Prefix</th>
          <th style="text-align:left;padding:0.75rem;color:#94a3b8;font-size:0.85rem;">Status</th>
          <th style="text-align:left;padding:0.75rem;color:#94a3b8;font-size:0.85rem;">Created</th>
          <th style="text-align:right;padding:0.75rem;color:#94a3b8;font-size:0.85rem;">Actions</th>
        </tr>
      </thead>
      <tbody>
        {#each data.clients as client}
          <tr style="border-bottom:1px solid #1e293b;">
            <td style="padding:0.75rem;font-weight:500;">{client.name}</td>
            <td style="padding:0.75rem;font-family:monospace;color:#93c5fd;">{client.ip}</td>
            <td style="padding:0.75rem;font-family:monospace;color:#fbbf24;">{client.tech_prefix}</td>
            <td style="padding:0.75rem;">
              <span style="padding:0.15rem 0.5rem;border-radius:9999px;font-size:0.75rem;background:{client.enabled ? '#166534' : '#991b1b'};">
                {client.enabled ? 'Active' : 'Disabled'}
              </span>
            </td>
            <td style="padding:0.75rem;color:#94a3b8;font-size:0.85rem;">{new Date(client.created_at).toLocaleDateString()}</td>
            <td style="padding:0.75rem;text-align:right;">
              <a href="/clients/{client.id}" style="color:#60a5fa;text-decoration:none;font-size:0.85rem;">Manage</a>
            </td>
          </tr>
        {:else}
          <tr><td colspan="6" style="padding:2rem;text-align:center;color:#64748b;">No clients yet. Click "+ Add Client" to get started.</td></tr>
        {/each}
      </tbody>
    </table>
  </div>
</div>

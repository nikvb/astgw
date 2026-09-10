<script lang="ts">
  let { data } = $props();
</script>

<div style="max-width:1100px;margin:0 auto;padding:1.5rem;">
  <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:1.5rem;">
    <div style="display:flex;align-items:center;gap:1rem;">
      <a href="/" style="color:#60a5fa;text-decoration:none;">← Back</a>
      <h1 style="font-size:1.3rem;">Gateways</h1>
    </div>
    <a href="/gateways/new" style="padding:0.4rem 1rem;background:#16a34a;color:white;border-radius:4px;text-decoration:none;font-size:0.9rem;">+ Add Gateway</a>
  </div>

  <div style="background:#1e293b;border-radius:6px;overflow:hidden;margin-bottom:1rem;">
    <table style="width:100%;border-collapse:collapse;">
      <thead>
        <tr style="border-bottom:1px solid #334155;">
          <th style="text-align:left;padding:0.75rem;color:#94a3b8;font-size:0.85rem;">Name</th>
          <th style="text-align:left;padding:0.75rem;color:#94a3b8;font-size:0.85rem;">IP</th>
          <th style="text-align:left;padding:0.75rem;color:#94a3b8;font-size:0.85rem;">Port</th>
          <th style="text-align:left;padding:0.75rem;color:#94a3b8;font-size:0.85rem;">Endpoint</th>
          <th style="text-align:left;padding:0.75rem;color:#94a3b8;font-size:0.85rem;">Weight</th>
          <th style="text-align:left;padding:0.75rem;color:#94a3b8;font-size:0.85rem;">Status</th>
          <th style="text-align:left;padding:0.75rem;color:#94a3b8;font-size:0.85rem;">Added</th>
          <th style="text-align:right;padding:0.75rem;color:#94a3b8;font-size:0.85rem;">Actions</th>
        </tr>
      </thead>
      <tbody>
        {#each data.gateways as gw}
          <tr style="border-bottom:1px solid #0f172a;">
            <td style="padding:0.75rem;font-weight:500;">
              {gw.name}
              {#if gw.is_default}
                <span style="margin-left:0.4rem;padding:0.1rem 0.45rem;border-radius:9999px;font-size:0.7rem;background:#1d4ed8;color:#dbeafe;">DEFAULT</span>
              {/if}
            </td>
            <td style="padding:0.75rem;font-family:monospace;color:#93c5fd;">{gw.ip}</td>
            <td style="padding:0.75rem;font-family:monospace;color:#94a3b8;">{gw.port}</td>
            <td style="padding:0.75rem;font-family:monospace;color:#94a3b8;font-size:0.8rem;">{gw.endpoint || 'gateway-' + gw.name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '')}</td>
            <td style="padding:0.75rem;font-family:monospace;color:#fbbf24;">{gw.weight}</td>
            <td style="padding:0.75rem;">
              <span style="padding:0.15rem 0.5rem;border-radius:9999px;font-size:0.75rem;background:{gw.enabled ? '#166534' : '#991b1b'};">
                {gw.enabled ? 'Active' : 'Disabled'}
              </span>
            </td>
            <td style="padding:0.75rem;color:#94a3b8;font-size:0.85rem;">{new Date(gw.created_at).toLocaleDateString()}</td>
            <td style="padding:0.75rem;text-align:right;">
              <a href="/gateways/{gw.id}" style="color:#60a5fa;text-decoration:none;font-size:0.85rem;">Manage</a>
            </td>
          </tr>
        {:else}
          <tr><td colspan="8" style="padding:2rem;text-align:center;color:#64748b;">No gateways yet. Click "+ Add Gateway" to get started.</td></tr>
        {/each}
      </tbody>
    </table>
  </div>

  <div style="background:#1e293b;padding:1rem 1.5rem;border-radius:6px;color:#94a3b8;font-size:0.85rem;">
    <p style="margin-bottom:0.5rem;">
      <strong style="color:#e2e8f0;">Default gateway:</strong> used by every client that has no gateway assigned to it.
      A client that <em>does</em> have gateways assigned goes only to those — never to the default.
    </p>
    <p>
      <strong style="color:#e2e8f0;">Per-client routing:</strong> weighted (load balance) or failover (priority order),
      set on each client's page. The AGI script <code style="color:#93c5fd;">/var/lib/asterisk/agi-bin/gateway_select.py</code> resolves it at call time.
    </p>
  </div>
</div>

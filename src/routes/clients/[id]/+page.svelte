<script lang="ts">
  let { data } = $props();
  let confirming = $state(false);
</script>

<div style="max-width:640px;margin:0 auto;padding:1.5rem;">
  <div style="display:flex;align-items:center;gap:1rem;margin-bottom:1.5rem;">
    <a href="/" style="color:#60a5fa;text-decoration:none;">← Back</a>
    <h1 style="font-size:1.3rem;">Client: {data.client.name}</h1>
  </div>

  <div style="background:#1e293b;padding:1.5rem;border-radius:6px;margin-bottom:1rem;">
    <div style="display:grid;grid-template-columns:120px 1fr;gap:0.75rem;align-items:center;">
      <span style="color:#94a3b8;">Name:</span>
      <span style="font-weight:500;">{data.client.name}</span>

      <span style="color:#94a3b8;">IP:</span>
      <span style="font-family:monospace;color:#93c5fd;">{data.client.ip}</span>

      <span style="color:#94a3b8;">Tech Prefix:</span>
      <span style="font-family:monospace;color:#fbbf24;">{data.client.tech_prefix}</span>

      <span style="color:#94a3b8;">Status:</span>
      <span>
        <span style="padding:0.15rem 0.5rem;border-radius:9999px;font-size:0.75rem;background:{data.client.enabled ? '#166534' : '#991b1b'};">
          {data.client.enabled ? 'Active' : 'Disabled'}
        </span>
      </span>

      <span style="color:#94a3b8;">Created:</span>
      <span style="color:#94a3b8;">{new Date(data.client.created_at).toLocaleString()}</span>
    </div>
  </div>

  <div style="display:flex;gap:0.75rem;">
    <form method="POST" action="?/toggle" style="flex:1;">
      <button type="submit"
        style="width:100%;padding:0.5rem;background:{data.client.enabled ? '#ca8a04' : '#16a34a'};color:white;border:none;border-radius:4px;cursor:pointer;">
        {data.client.enabled ? 'Disable' : 'Enable'}
      </button>
    </form>

    {#if !confirming}
      <button onclick={() => confirming = true}
        style="flex:1;padding:0.5rem;background:#dc2626;color:white;border:none;border-radius:4px;cursor:pointer;">
        Delete
      </button>
    {:else}
      <form method="POST" action="?/delete" style="flex:1;display:flex;gap:0.5rem;">
        <button type="submit"
          style="flex:1;padding:0.5rem;background:#991b1b;color:white;border:none;border-radius:4px;cursor:pointer;">
          Confirm Delete
        </button>
        <button type="button" onclick={() => confirming = false}
          style="padding:0.5rem 0.75rem;background:#475569;color:white;border:none;border-radius:4px;cursor:pointer;">
          Cancel
        </button>
      </form>
    {/if}
  </div>

  <!-- Gateways -->
  <div style="background:#1e293b;padding:1.5rem;border-radius:6px;margin-top:1.5rem;">
    <h2 style="font-size:1.05rem;margin-bottom:0.25rem;">Gateways</h2>
    <p style="color:#94a3b8;font-size:0.8rem;margin-bottom:1rem;">
      Outbound gateways for this client. Assigned gateways are the only route used —
      calls never fall back anywhere else. With none assigned, the client uses
      {#if data.defaultGateway}
        the default gateway <strong style="color:#e2e8f0;">{data.defaultGateway.name}</strong>
        <code style="color:#93c5fd;">{data.defaultGateway.ip}:{data.defaultGateway.port}</code>.
      {:else}
        <code style="color:#93c5fd;">voip-switch</code>.
      {/if}
    </p>

    <form method="POST" action="?/set_mode" style="display:flex;align-items:center;gap:0.5rem;margin-bottom:1rem;">
      <label style="color:#94a3b8;font-size:0.85rem;">Mode:</label>
      <select name="gateway_mode" style="background:#0f172a;color:#e2e8f0;border:1px solid #334155;border-radius:4px;padding:0.3rem 0.5rem;">
        <option value="weighted" selected={data.client.gateway_mode !== 'failover'}>Weighted (round-robin)</option>
        <option value="failover" selected={data.client.gateway_mode === 'failover'}>Failover (priority order)</option>
      </select>
      <button type="submit" style="padding:0.3rem 0.75rem;background:#2563eb;color:white;border:none;border-radius:4px;cursor:pointer;font-size:0.85rem;">Save</button>
    </form>

    <table style="width:100%;border-collapse:collapse;margin-bottom:1rem;">
      <thead>
        <tr style="border-bottom:1px solid #334155;">
          <th style="text-align:left;padding:0.4rem;color:#94a3b8;font-size:0.75rem;">Gateway</th>
          <th style="text-align:left;padding:0.4rem;color:#94a3b8;font-size:0.75rem;">Weight / Priority</th>
        </tr>
      </thead>
      <tbody>
        {#each data.assignedGateways as gw}
          <tr style="border-bottom:1px solid #0f172a;">
            <td style="padding:0.4rem;font-weight:500;">{gw.name} <span style="font-family:monospace;color:#93c5fd;font-size:0.8rem;">{gw.ip}:{gw.port}</span></td>
            <td style="padding:0.4rem;">
              <form method="POST" action="?/update_gateway" style="display:flex;gap:0.4rem;align-items:center;">
                <input type="hidden" name="gateway_id" value={gw.gateway_id} />
                <input type="number" name="weight" value={gw.weight} min="1" title="Weight (weighted mode)" style="width:56px;background:#0f172a;color:#fbbf24;border:1px solid #334155;border-radius:4px;padding:0.2rem;" />
                <input type="number" name="priority" value={gw.priority} min="1" title="Priority (failover order)" style="width:56px;background:#0f172a;color:#e2e8f0;border:1px solid #334155;border-radius:4px;padding:0.2rem;" />
                <button type="submit" style="padding:0.2rem 0.5rem;background:#475569;color:white;border:none;border-radius:4px;cursor:pointer;font-size:0.8rem;">Update</button>
                <button type="submit" formaction="?/unassign_gateway" style="padding:0.2rem 0.5rem;background:#991b1b;color:white;border:none;border-radius:4px;cursor:pointer;font-size:0.8rem;">Remove</button>
              </form>
            </td>
          </tr>
        {:else}
          <tr><td colspan="2" style="padding:1rem;text-align:center;color:#64748b;font-size:0.85rem;">No gateways assigned — using {data.defaultGateway ? data.defaultGateway.name + ' (default)' : 'voip-switch'}.</td></tr>
        {/each}
      </tbody>
    </table>

    {#if data.availableGateways.length > 0}
      <form method="POST" action="?/assign_gateway" style="display:flex;gap:0.4rem;align-items:center;flex-wrap:wrap;">
        <select name="gateway_id" required style="flex:1;min-width:160px;background:#0f172a;color:#e2e8f0;border:1px solid #334155;border-radius:4px;padding:0.35rem;">
          <option value="" disabled selected>Add a gateway…</option>
          {#each data.availableGateways as g}
            <option value={g.id}>{g.name} ({g.ip}:{g.port})</option>
          {/each}
        </select>
        <input type="number" name="weight" value="1" min="1" title="Weight" style="width:56px;background:#0f172a;color:#fbbf24;border:1px solid #334155;border-radius:4px;padding:0.35rem;" />
        <input type="number" name="priority" value="1" min="1" title="Priority" style="width:56px;background:#0f172a;color:#e2e8f0;border:1px solid #334155;border-radius:4px;padding:0.35rem;" />
        <button type="submit" style="padding:0.35rem 0.9rem;background:#16a34a;color:white;border:none;border-radius:4px;cursor:pointer;">Assign</button>
      </form>
    {:else}
      <p style="color:#64748b;font-size:0.85rem;">All enabled gateways are assigned. <a href="/gateways/new" style="color:#60a5fa;">Add a gateway</a> to assign more.</p>
    {/if}
  </div>
</div>

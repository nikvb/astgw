<script lang="ts">
  import type { PageData, ActionData } from "./$types";
  let { data, form }: { data: PageData; form: ActionData } = $props();
  const gw = $derived(data.gateway);
</script>

<div style="max-width:500px;margin:0 auto;padding:1.5rem;">
  <div style="display:flex;align-items:center;gap:1rem;margin-bottom:1.5rem;">
    <a href="/gateways" style="color:#60a5fa;text-decoration:none;">← Back</a>
    <h1 style="font-size:1.3rem;">Manage Gateway</h1>
    {#if gw.is_default}
      <span style="padding:0.1rem 0.45rem;border-radius:9999px;font-size:0.7rem;background:#1d4ed8;color:#dbeafe;">DEFAULT</span>
    {/if}
  </div>

  {#if form?.error}
    <div style="background:#991b1b;padding:0.5rem 1rem;border-radius:4px;margin-bottom:1rem;">{form.error}</div>
  {/if}
  {#if form?.success}
    <div style="background:#166534;padding:0.5rem 1rem;border-radius:4px;margin-bottom:1rem;">{form.success}</div>
  {/if}

  <form method="POST" action="?/update" style="background:#1e293b;padding:1.5rem;border-radius:6px;margin-bottom:1rem;">
    <label style="display:block;margin-bottom:1rem;">
      <span style="display:block;margin-bottom:0.25rem;color:#94a3b8;font-size:0.85rem;">Name</span>
      <input name="name" value={gw.name} required
        style="width:100%;padding:0.5rem;background:#334155;border:1px solid #475569;border-radius:4px;color:#e2e8f0;" />
    </label>
    <div style="display:flex;gap:0.75rem;margin-bottom:1rem;">
      <label style="flex:2;">
        <span style="display:block;margin-bottom:0.25rem;color:#94a3b8;font-size:0.85rem;">IP</span>
        <input name="ip" value={gw.ip} required
          style="width:100%;padding:0.5rem;background:#334155;border:1px solid #475569;border-radius:4px;color:#e2e8f0;font-family:monospace;" />
      </label>
      <label style="flex:1;">
        <span style="display:block;margin-bottom:0.25rem;color:#94a3b8;font-size:0.85rem;">Port</span>
        <input name="port" type="number" value={gw.port} min="1" max="65535" required
          style="width:100%;padding:0.5rem;background:#334155;border:1px solid #475569;border-radius:4px;color:#e2e8f0;font-family:monospace;" />
      </label>
      <label style="flex:1;">
        <span style="display:block;margin-bottom:0.25rem;color:#94a3b8;font-size:0.85rem;">Weight</span>
        <input name="weight" type="number" value={gw.weight} min="1" max="100" required
          style="width:100%;padding:0.5rem;background:#334155;border:1px solid #475569;border-radius:4px;color:#e2e8f0;font-family:monospace;" />
      </label>
    </div>
    <div style="color:#64748b;font-size:0.78rem;margin-bottom:1rem;">
      PJSIP endpoint: <code style="color:#93c5fd;">{gw.endpoint || 'gateway-' + gw.name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '')}</code>
      {#if gw.endpoint}
        — an existing realtime endpoint; saving updates its address and reloads PJSIP on all servers.
      {/if}
    </div>
    <button type="submit"
      style="width:100%;padding:0.6rem;background:#2563eb;color:white;border:none;border-radius:4px;cursor:pointer;font-size:0.95rem;">
      Save Gateway
    </button>
  </form>

  <div style="background:#1e293b;padding:1.5rem;border-radius:6px;margin-bottom:1rem;">
    <h2 style="font-size:1rem;margin-bottom:0.5rem;color:#e2e8f0;">Default route</h2>
    {#if gw.is_default}
      <p style="color:#94a3b8;font-size:0.85rem;margin-bottom:0.75rem;">
        Every client with no gateway of its own is routed here.
      </p>
      <form method="POST" action="?/clear_default">
        <button type="submit" style="padding:0.4rem 0.9rem;background:#475569;color:white;border:none;border-radius:4px;cursor:pointer;font-size:0.85rem;">
          Clear default
        </button>
      </form>
    {:else}
      <p style="color:#94a3b8;font-size:0.85rem;margin-bottom:0.75rem;">
        Make this the route for every client that has no gateway assigned.
      </p>
      <form method="POST" action="?/set_default">
        <button type="submit" style="padding:0.4rem 0.9rem;background:#1d4ed8;color:white;border:none;border-radius:4px;cursor:pointer;font-size:0.85rem;">
          Make default
        </button>
      </form>
    {/if}
  </div>

  <div style="display:flex;gap:0.75rem;">
    <form method="POST" action="?/toggle" style="flex:1;">
      <button type="submit" style="width:100%;padding:0.5rem;background:#475569;color:white;border:none;border-radius:4px;cursor:pointer;">
        {gw.enabled ? 'Disable' : 'Enable'}
      </button>
    </form>
    <form method="POST" action="?/delete" style="flex:1;"
      onsubmit={(e) => { if (!confirm('Delete gateway ' + gw.name + '?')) e.preventDefault(); }}>
      <button type="submit" style="width:100%;padding:0.5rem;background:#dc2626;color:white;border:none;border-radius:4px;cursor:pointer;">
        Delete
      </button>
    </form>
  </div>
</div>

<script lang="ts">
  import type { PageData, ActionData } from "./$types";
  let { data, form }: { data: PageData; form: ActionData } = $props();
  const gw = data.gateway;
</script>

<div style="max-width:500px;margin:0 auto;padding:1.5rem;">
  <div style="display:flex;align-items:center;gap:1rem;margin-bottom:1.5rem;">
    <a href="/gateways" style="color:#60a5fa;text-decoration:none;">← Back</a>
    <h1 style="font-size:1.3rem;">Manage Gateway</h1>
  </div>

  {#if form?.error}
    <div style="background:#991b1b;padding:0.5rem 1rem;border-radius:4px;margin-bottom:1rem;">{form.error}</div>
  {/if}

  <div style="background:#1e293b;padding:1.5rem;border-radius:6px;margin-bottom:1rem;">
    <div style="margin-bottom:0.75rem;">
      <span style="color:#94a3b8;font-size:0.85rem;">Name</span>
      <div style="font-weight:500;margin-top:0.2rem;">{gw.name}</div>
    </div>
    <div style="margin-bottom:0.75rem;">
      <span style="color:#94a3b8;font-size:0.85rem;">IP</span>
      <div style="font-family:monospace;color:#93c5fd;margin-top:0.2rem;">{gw.ip}:{gw.port}</div>
    </div>
    <div style="margin-bottom:0.75rem;">
      <span style="color:#94a3b8;font-size:0.85rem;">Weight</span>
      <div style="font-family:monospace;color:#fbbf24;margin-top:0.2rem;">{gw.weight}</div>
    </div>
    <div>
      <span style="color:#94a3b8;font-size:0.85rem;">Status</span>
      <div style="margin-top:0.2rem;">
        <span style="padding:0.15rem 0.5rem;border-radius:9999px;font-size:0.75rem;background:{gw.enabled ? '#166534' : '#991b1b'};">
          {gw.enabled ? 'Active' : 'Disabled'}
        </span>
      </div>
    </div>
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

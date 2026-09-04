<script lang="ts">
  let { data } = $props();
  let confirming = $state(false);
</script>

<div style="max-width:500px;margin:0 auto;padding:1.5rem;">
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
</div>

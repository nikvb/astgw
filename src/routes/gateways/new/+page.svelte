<script lang="ts">
  import type { ActionData } from "./$types";
  let { form }: { form: ActionData } = $props();
</script>

<div style="max-width:500px;margin:0 auto;padding:1.5rem;">
  <div style="display:flex;align-items:center;gap:1rem;margin-bottom:1.5rem;">
    <a href="/gateways" style="color:#60a5fa;text-decoration:none;">← Back</a>
    <h1 style="font-size:1.3rem;">Add Gateway</h1>
  </div>

  {#if form?.error}
    <div style="background:#991b1b;padding:0.5rem 1rem;border-radius:4px;margin-bottom:1rem;">{form.error}</div>
  {/if}

  <form method="POST" style="background:#1e293b;padding:1.5rem;border-radius:6px;">
    <label style="display:block;margin-bottom:1rem;">
      <span style="display:block;margin-bottom:0.25rem;color:#94a3b8;font-size:0.85rem;">Gateway Name</span>
      <input name="name" placeholder="e.g. ConnexCS-Primary" required
        style="width:100%;padding:0.5rem;background:#334155;border:1px solid #475569;border-radius:4px;color:#e2e8f0;" />
    </label>
    <label style="display:block;margin-bottom:1rem;">
      <span style="display:block;margin-bottom:0.25rem;color:#94a3b8;font-size:0.85rem;">IP Address</span>
      <input name="ip" placeholder="e.g. 203.0.113.10" required pattern={"\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}"}
        style="width:100%;padding:0.5rem;background:#334155;border:1px solid #475569;border-radius:4px;color:#e2e8f0;" />
    </label>
    <label style="display:block;margin-bottom:1rem;">
      <span style="display:block;margin-bottom:0.25rem;color:#94a3b8;font-size:0.85rem;">SIP Port</span>
      <input name="port" type="number" value="5060" min="1" max="65535" required
        style="width:100%;padding:0.5rem;background:#334155;border:1px solid #475569;border-radius:4px;color:#e2e8f0;" />
    </label>
    <label style="display:block;margin-bottom:1.5rem;">
      <span style="display:block;margin-bottom:0.25rem;color:#94a3b8;font-size:0.85rem;">Weight <span style="color:#64748b;">(1–100, higher = more traffic)</span></span>
      <input name="weight" type="number" value="1" min="1" max="100" required
        style="width:100%;padding:0.5rem;background:#334155;border:1px solid #475569;border-radius:4px;color:#e2e8f0;" />
    </label>
    <label style="display:flex;align-items:center;gap:0.5rem;margin-bottom:1.5rem;color:#94a3b8;font-size:0.85rem;">
      <input name="is_default" type="checkbox" value="1" style="width:auto;" />
      Make this the default gateway (used by clients with no gateway assigned)
    </label>
    <button type="submit"
      style="width:100%;padding:0.5rem;background:#16a34a;color:white;border:none;border-radius:4px;cursor:pointer;font-size:1rem;">
      Add Gateway
    </button>
  </form>
</div>

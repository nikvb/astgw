<script lang="ts">
  import type { ActionData } from "./$types";
  let { form }: { form: ActionData } = $props();
</script>

<div style="max-width:500px;margin:0 auto;padding:1.5rem;">
  <div style="display:flex;align-items:center;gap:1rem;margin-bottom:1.5rem;">
    <a href="/" style="color:#60a5fa;text-decoration:none;">← Back</a>
    <h1 style="font-size:1.3rem;">Add Client</h1>
  </div>

  {#if form?.error}
    <div style="background:#991b1b;padding:0.5rem 1rem;border-radius:4px;margin-bottom:1rem;">{form.error}</div>
  {/if}

  <form method="POST" style="background:#1e293b;padding:1.5rem;border-radius:6px;">
    <label style="display:block;margin-bottom:1rem;">
      <span style="display:block;margin-bottom:0.25rem;color:#94a3b8;font-size:0.85rem;">Client Name</span>
      <input name="name" placeholder="e.g. Acme Corp" required
        style="width:100%;padding:0.5rem;background:#334155;border:1px solid #475569;border-radius:4px;color:#e2e8f0;" />
    </label>
    <label style="display:block;margin-bottom:1rem;">
      <span style="display:block;margin-bottom:0.25rem;color:#94a3b8;font-size:0.85rem;">Client IP</span>
      <input name="ip" placeholder="e.g. 192.168.1.100" required pattern={"\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}(/\\d{1,2})?"}
        style="width:100%;padding:0.5rem;background:#334155;border:1px solid #475569;border-radius:4px;color:#e2e8f0;" />
    </label>
    <label style="display:block;margin-bottom:1rem;">
      <span style="display:block;margin-bottom:0.25rem;color:#94a3b8;font-size:0.85rem;">Tech Prefix</span>
      <input name="tech_prefix" placeholder="e.g. 777#" required
        style="width:100%;padding:0.5rem;background:#334155;border:1px solid #475569;border-radius:4px;color:#e2e8f0;" />
    </label>
    <label style="display:block;margin-bottom:1.5rem;">
      <span style="display:block;margin-bottom:0.25rem;color:#94a3b8;font-size:0.85rem;">AMD Reject Status</span>
      <select name="amd_reject"
        style="width:100%;padding:0.5rem;background:#334155;border:1px solid #475569;border-radius:4px;color:#e2e8f0;">
        <option value="603" selected>603 Decline (default)</option>
        <option value="403">403 Forbidden</option>
      </select>
      <span style="display:block;margin-top:0.25rem;color:#64748b;font-size:0.75rem;">
        SIP status returned to this client when AMD detects an answering machine.
      </span>
    </label>
    <button type="submit"
      style="width:100%;padding:0.5rem;background:#16a34a;color:white;border:none;border-radius:4px;cursor:pointer;font-size:1rem;">
      Add Client
    </button>
  </form>
</div>

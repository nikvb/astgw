<script lang="ts">
  import type { ActionData } from "./$types";
  let { data, form }: { data: any; form: ActionData } = $props();
</script>

<div style="max-width:500px;margin:0 auto;padding:1.5rem;">
  <div style="display:flex;align-items:center;gap:1rem;margin-bottom:1.5rem;">
    <a href="/" style="color:#60a5fa;text-decoration:none;">← Back</a>
    <h1 style="font-size:1.3rem;">Settings</h1>
  </div>

  {#if form?.error}
    <div style="background:#991b1b;padding:0.5rem 1rem;border-radius:4px;margin-bottom:1rem;">{form.error}</div>
  {/if}
  {#if form?.success}
    <div style="background:#166534;padding:0.5rem 1rem;border-radius:4px;margin-bottom:1rem;">Settings saved.</div>
  {/if}

  <form method="POST" action="?/save" style="background:#1e293b;padding:1.5rem;border-radius:6px;">
    <label style="display:block;margin-bottom:1rem;">
      <span style="display:block;margin-bottom:0.25rem;color:#94a3b8;font-size:0.85rem;">VOIP Switch IP</span>
      <input name="voip_switch_ip" value={data.settings.voip_switch_ip || ''} required
        style="width:100%;padding:0.5rem;background:#334155;border:1px solid #475569;border-radius:4px;color:#e2e8f0;" />
    </label>
    <label style="display:block;margin-bottom:1.5rem;">
      <span style="display:block;margin-bottom:0.25rem;color:#94a3b8;font-size:0.85rem;">SIP Port</span>
      <input name="sip_port" value={data.settings.sip_port || '5060'}
        style="width:100%;padding:0.5rem;background:#334155;border:1px solid #475569;border-radius:4px;color:#e2e8f0;" />
    </label>
    <button type="submit"
      style="width:100%;padding:0.5rem;background:#2563eb;color:white;border:none;border-radius:4px;cursor:pointer;font-size:1rem;">
      Save Settings
    </button>
  </form>
</div>

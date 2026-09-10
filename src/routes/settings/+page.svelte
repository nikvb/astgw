<script lang="ts">
  import type { ActionData, PageData } from "./$types";
  let { data, form }: { data: PageData; form: ActionData } = $props();
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
    <div style="background:#166534;padding:0.5rem 1rem;border-radius:4px;margin-bottom:1rem;">{form.success}</div>
  {/if}

  <div style="background:#1e293b;padding:1.5rem;border-radius:6px;margin-bottom:1.5rem;">
    <h2 style="font-size:1rem;margin-bottom:0.5rem;color:#e2e8f0;">Routing</h2>
    {#if data.defaultGateway}
      <p style="color:#94a3b8;font-size:0.85rem;margin-bottom:0.75rem;">
        The VOIP switch is now a gateway — <strong style="color:#e2e8f0;">{data.defaultGateway.name}</strong>
        <code style="color:#93c5fd;">{data.defaultGateway.ip}:{data.defaultGateway.port}</code> — and is the
        default route for any client with no gateway of its own.
      </p>
      <a href="/gateways/{data.defaultGateway.id}" style="color:#60a5fa;text-decoration:none;font-size:0.9rem;">Manage it on the Gateways page →</a>
    {:else}
      <p style="color:#94a3b8;font-size:0.85rem;margin-bottom:0.75rem;">
        No default gateway is set. Clients with no gateway of their own fall back to the
        <code style="color:#93c5fd;">voip-switch</code> endpoint.
      </p>
      <a href="/gateways" style="color:#60a5fa;text-decoration:none;font-size:0.9rem;">Set one on the Gateways page →</a>
    {/if}
  </div>

  <form method="POST" action="?/password" style="background:#1e293b;padding:1.5rem;border-radius:6px;">
    <h2 style="font-size:1rem;margin-bottom:1rem;color:#e2e8f0;">Change Password</h2>
    <label style="display:block;margin-bottom:1rem;">
      <span style="display:block;margin-bottom:0.25rem;color:#94a3b8;font-size:0.85rem;">Current Password</span>
      <input name="current_password" type="password" required
        style="width:100%;padding:0.5rem;background:#334155;border:1px solid #475569;border-radius:4px;color:#e2e8f0;" />
    </label>
    <label style="display:block;margin-bottom:1rem;">
      <span style="display:block;margin-bottom:0.25rem;color:#94a3b8;font-size:0.85rem;">New Password</span>
      <input name="new_password" type="password" required minlength="4"
        style="width:100%;padding:0.5rem;background:#334155;border:1px solid #475569;border-radius:4px;color:#e2e8f0;" />
    </label>
    <label style="display:block;margin-bottom:1.5rem;">
      <span style="display:block;margin-bottom:0.25rem;color:#94a3b8;font-size:0.85rem;">Confirm New Password</span>
      <input name="confirm_password" type="password" required minlength="4"
        style="width:100%;padding:0.5rem;background:#334155;border:1px solid #475569;border-radius:4px;color:#e2e8f0;" />
    </label>
    <button type="submit"
      style="width:100%;padding:0.6rem;background:#2563eb;color:white;border:none;border-radius:4px;cursor:pointer;font-size:0.95rem;">
      Change Password
    </button>
  </form>
</div>

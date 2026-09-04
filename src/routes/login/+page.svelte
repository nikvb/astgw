<script lang="ts">
  import type { ActionData } from "./$types";
  let { form }: { form: ActionData } = $props();
</script>

<div style="display:flex;align-items:center;justify-content:center;min-height:100vh;">
  <div style="background:#1e293b;padding:2rem;border-radius:8px;width:360px;">
    <h1 style="font-size:1.5rem;margin-bottom:1.5rem;text-align:center;">AstGW Manager</h1>
    {#if form?.error}
      <div style="background:#991b1b;padding:0.5rem;border-radius:4px;margin-bottom:1rem;text-align:center;">{form.error}</div>
    {/if}
    <form method="POST">
      <input name="username" placeholder="Username" required
        style="width:100%;padding:0.5rem;margin-bottom:0.75rem;background:#334155;border:1px solid #475569;border-radius:4px;color:#e2e8f0;" />
      <input name="password" type="password" placeholder="Password" required
        style="width:100%;padding:0.5rem;margin-bottom:1rem;background:#334155;border:1px solid #475569;border-radius:4px;color:#e2e8f0;" />
      <button type="submit"
        style="width:100%;padding:0.5rem;background:#2563eb;color:white;border:none;border-radius:4px;cursor:pointer;font-size:1rem;">
        Login
      </button>
    </form>
  </div>
</div>

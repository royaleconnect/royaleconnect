// Daily fee job (late fees + reminders). The work itself now happens inside the database in one step
// (public.nightly_fees_run, scheduled by pg_cron as job rc-nightly-fees at 06:05 IST), so there is no 1,000-row limit and
// no row-by-row traffic. This function stays for manual runs and for an older schedule that still calls it.
// Protected: only the scheduler (x-cron-key) or the service key may call. Idempotent: safe to run twice in a day.
import { admin, isScheduler, json } from "../_shared/lib.ts";

Deno.serve(async (req) => {
  if (!(await isScheduler(req))) return json({ error: "forbidden" }, 403);
  const { data, error } = await admin().rpc("nightly_fees_run", {});
  if (error) { console.error("nightly_fees_run", error.message); return json({ ok: false, error: error.message }, 500); }
  return json(data);
});

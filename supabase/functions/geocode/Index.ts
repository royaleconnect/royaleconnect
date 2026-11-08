// POST /functions/v1/geocode   { route_id }     (bearer: transport in-charge / office / IT / principal / vice principal)
// "Place pins from addresses": for each child on that bus whose pin is missing or still comes from the address,
// look the address up on Google Maps (Geocoding API, India, near Bengaluru) and save the pin.
// Vague results (partial match, or only an approximate area) are saved as "check" (amber) so the transport office looks at them.
// Pins placed by a family or by the transport office are never overwritten.
// Needs the secret GOOGLE_MAPS_KEY. Without it the answer is { error: "Map key not set yet" }.
// deno-lint-ignore-file no-explicit-any
import { admin, json, preflight, liveClaims, audit } from "../_shared/lib.ts";

const ALLOWED = ["transport_incharge", "office", "it_admin", "principal", "vice_principal"];
const MAX_PER_CALL = 120;                       // stays well inside the function time limit; press again for the rest
const BLR_BOUNDS = "12.80,77.40|13.20,77.85";   // Bengaluru, to prefer local matches

function areaOf(r: any): string | null {
  const comps: any[] = r?.address_components ?? [];
  const pick = (t: string) => comps.find((c) => (c.types ?? []).includes(t))?.long_name ?? null;
  return pick("sublocality_level_2") ?? pick("sublocality_level_1") ?? pick("neighborhood") ?? pick("locality");
}

Deno.serve(async (req) => {
  const pf = preflight(req); if (pf) return pf;
  try {
    const c = await liveClaims(req);
    if (!c) return json({ error: "Please sign in again." }, 401);
    if (c.view_only) return json({ error: "This is a read-only view." }, 403);
    if (!c.staff_id || !(c.roles ?? []).some((r: string) => ALLOWED.includes(r))) return json({ error: "Not allowed." }, 403);
    const key = Deno.env.get("GOOGLE_MAPS_KEY");
    if (!key) return json({ error: "Map key not set yet" }, 400);

    const body = await req.json().catch(() => ({}));
    const routeId = String(body.route_id ?? "");
    if (!/^[0-9a-f-]{36}$/i.test(routeId)) return json({ error: "Choose a bus first." }, 400);
    const db = admin();

    const { data: yr } = await db.from("academic_year").select("id").eq("is_current", true).maybeSingle();
    const { data: kids } = await db.from("transport_enrolment").select("student_id, student:student_id(address, active)")
      .eq("route_id", routeId).eq("academic_year_id", yr?.id ?? "00000000-0000-0000-0000-000000000000");
    const ids = (kids ?? []).filter((k: any) => k.student?.active).map((k: any) => k.student_id);
    const { data: pins } = ids.length ? await db.from("pickup_pin").select("student_id, source").in("student_id", ids) : { data: [] };
    const kept = new Set((pins ?? []).filter((p: any) => p.source !== "address").map((p: any) => p.student_id));
    const todo = (kids ?? []).filter((k: any) => k.student?.active && !kept.has(k.student_id) && String(k.student?.address ?? "").trim().length > 3);

    let placed = 0, vague = 0, failed = 0;
    for (const k of todo.slice(0, MAX_PER_CALL)) {
      const address = String(k.student.address).trim();
      const url = `https://maps.googleapis.com/maps/api/geocode/json?address=${encodeURIComponent(address + ", Bengaluru, Karnataka")}` +
        `&region=in&components=country:IN&bounds=${encodeURIComponent(BLR_BOUNDS)}&key=${key}`;
      try {
        const g = await (await fetch(url)).json();
        if (g.status === "REQUEST_DENIED") return json({ error: "The map key was refused by Google. Please check it." }, 400);
        const r = g.results?.[0];
        if (g.status !== "OK" || !r) { failed++; continue; }
        const loc = r.geometry?.location;
        const isVague = !!r.partial_match || r.geometry?.location_type === "APPROXIMATE";
        const { error } = await db.from("pickup_pin").upsert({
          student_id: k.student_id, lat: loc.lat, lng: loc.lng, source: "address", quality: isVague ? "check" : "ok",
          area: areaOf(r), updated_by_staff: c.staff_id, updated_at: new Date().toISOString(),
        });
        if (error) { failed++; continue; }
        placed++; if (isVague) vague++;
      } catch { failed++; }
    }
    await audit(db, { actor_staff_id: c.staff_id, action: "pins.geocode", entity: "route", entity_id: routeId, detail: { placed, vague, failed } });
    return json({ ok: true, placed, vague, failed, left: Math.max(0, todo.length - MAX_PER_CALL), no_address: (kids ?? []).filter((k: any) => k.student?.active && !kept.has(k.student_id) && String(k.student?.address ?? "").trim().length <= 3).length });
  } catch (e) {
    console.error(e);
    return json({ error: "Something went wrong. Please try again in a minute." }, 500);
  }
});

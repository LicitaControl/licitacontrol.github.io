// Avisos de LicitaControl por correo.
// Lo llama el cron cada 15 minutos (cron.sql) y el botón "Enviarme un correo de prueba" de la página.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const CRON_SECRET = Deno.env.get("CRON_SECRET") ?? "";
const SITE_URL = Deno.env.get("SITE_URL") ?? "";
const MAIL_FROM = Deno.env.get("MAIL_FROM") ?? "";
const MAIL_FROM_NAME = Deno.env.get("MAIL_FROM_NAME") ?? "LicitaControl";
const BREVO_API_KEY = Deno.env.get("BREVO_API_KEY");
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const TIPOS: Record<string, string> = { reducida: "Licitación reducida", menor: "Licitación menor", mayor: "Licitación mayor" };
const MES = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "set", "oct", "nov", "dic"];

const admin = createClient(SB_URL, SERVICE, { auth: { persistSession: false } });

const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...CORS, "Content-Type": "application/json" } });
const esc = (s: unknown) =>
  String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
const fmtFecha = (iso: string) => {
  const [y, m, d] = iso.split("-").map(Number);
  return `${d} ${MES[m - 1]} ${y}`;
};
// Costa Rica es UTC-6 todo el año.
const ahoraCR = () => {
  const d = new Date(Date.now() - 6 * 3600 * 1000);
  return { hoy: d.toISOString().slice(0, 10), min: d.getUTCHours() * 60 + d.getUTCMinutes() };
};
const dias = (desde: string, hasta: string) => Math.round((Date.parse(hasta) - Date.parse(desde)) / 86400000);
const cuando = (d: number) => (d === 0 ? "hoy" : d === 1 ? "mañana" : `en ${d} días`);

async function enviar(to: string, subject: string, html: string) {
  if (!MAIL_FROM) throw new Error("Falta el secreto MAIL_FROM");
  if (BREVO_API_KEY) {
    const r = await fetch("https://api.brevo.com/v3/smtp/email", {
      method: "POST",
      headers: { "api-key": BREVO_API_KEY, "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({ sender: { name: MAIL_FROM_NAME, email: MAIL_FROM }, to: [{ email: to }], subject, htmlContent: html }),
    });
    if (!r.ok) throw new Error(`Brevo ${r.status}: ${await r.text()}`);
    return;
  }
  if (RESEND_API_KEY) {
    const r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${RESEND_API_KEY}`, "content-type": "application/json" },
      body: JSON.stringify({ from: `${MAIL_FROM_NAME} <${MAIL_FROM}>`, to: [to], subject, html }),
    });
    if (!r.ok) throw new Error(`Resend ${r.status}: ${await r.text()}`);
    return;
  }
  throw new Error("Falta el secreto BREVO_API_KEY o RESEND_API_KEY");
}

function plantilla(titulo: string, detalle: string, l?: Record<string, string>) {
  const fila = (k: string, v: string) =>
    `<tr><td style="padding:4px 12px 4px 0;color:#667090">${k}</td><td style="padding:4px 0"><b>${esc(v)}</b></td></tr>`;
  return `<div style="font-family:Arial,sans-serif;max-width:520px;margin:auto;color:#18223a">
<h2 style="margin:0 0 6px">${esc(titulo)}</h2><p style="margin:0 0 14px;color:#667090">${esc(detalle)}</p>
${l ? `<table style="border-collapse:collapse;font-size:14px">${fila("Procedimiento", l.num)}${fila("Institución", l.inst)}${fila("Objeto", l.obj)}${fila("Tipo", TIPOS[l.tipo] ?? l.tipo)}${fila("Apertura", fmtFecha(l.apertura))}${fila("Entrega", fmtFecha(l.entrega))}</table>` : ""}
${SITE_URL ? `<p style="margin-top:18px"><a href="${esc(SITE_URL)}" style="background:#2f5fb3;color:#fff;padding:10px 16px;border-radius:8px;text-decoration:none">Abrir LicitaControl</a></p>` : ""}
<p style="margin-top:18px;font-size:12px;color:#667090">Recibes este correo porque tienes una licitación registrada en LicitaControl.</p></div>`;
}

async function procesar() {
  const { hoy, min } = ahoraCR();
  const { data: lics, error } = await admin.from("licitaciones").select("*").eq("estado", "Activa");
  if (error) throw error;
  if (!lics?.length) return { enviados: 0, errores: [] as string[] };

  const { data: ya } = await admin.from("avisos_enviados").select("licitacion_id,tipo,dias").in("licitacion_id", lics.map((l) => l.id));
  const enviado = new Set((ya ?? []).map((a) => `${a.licitacion_id}|${a.tipo}|${a.dias}`));
  const { data: perf } = await admin.from("perfiles").select("user_id,email").in("user_id", [...new Set(lics.map((l) => l.user_id))]);
  const correo = new Map((perf ?? []).map((p) => [p.user_id, p.email]));

  let enviados = 0;
  const errores: string[] = [];
  const marcar = (id: string, tipo: string, ns: number[]) =>
    admin.from("avisos_enviados").upsert(ns.map((n) => ({ licitacion_id: id, tipo, dias: n })), {
      onConflict: "licitacion_id,tipo,dias",
      ignoreDuplicates: true,
    });

  for (const l of lics) {
    const to = correo.get(l.user_id);
    if (!to) continue;
    for (const tipo of ["apertura", "entrega"] as const) {
      // Cada fecha tiene sus propios días de aviso y su propia hora.
      const avisos: number[] = l[tipo === "apertura" ? "al_apertura" : "al_entrega"] ?? [];
      const [hh, mm] = String(l[tipo === "apertura" ? "hora_apertura" : "hora_entrega"] ?? "08:00").split(":").map(Number);
      const horaMin = hh * 60 + mm;
      const d = dias(hoy, l[tipo]);
      const nombre = tipo === "apertura" ? "Apertura de ofertas" : "Entrega";
      try {
        if (d >= 0) {
          // Avisos que ya les toca: faltan menos días que n, o es el día exacto y ya pasó la hora.
          if (!avisos.length) continue;
          const toca = avisos.filter((n) => d < n || (d === n && min >= horaMin));
          if (!toca.length) continue;
          const m = Math.min(...toca);
          if (enviado.has(`${l.id}|${tipo}|${m}`)) continue;
          await enviar(to, `${nombre} ${cuando(d)} · ${l.num}`, plantilla(`${nombre} ${cuando(d)}`, `${l.inst}`, l));
          await marcar(l.id, tipo, toca);
          toca.forEach((n) => enviado.add(`${l.id}|${tipo}|${n}`));
          enviados++;
        } else if (tipo === "entrega" && d >= -3 && !enviado.has(`${l.id}|entrega|-1`)) {
          await enviar(to, `Entrega vencida · ${l.num}`, plantilla("Entrega vencida", `La fecha de entrega fue el ${fmtFecha(l.entrega)} y la licitación sigue sin marcarse como entregada.`, l));
          await marcar(l.id, "entrega", [-1]);
          enviado.add(`${l.id}|entrega|-1`);
          enviados++;
        }
      } catch (e) {
        errores.push(`${l.num}: ${e instanceof Error ? e.message : String(e)}`);
      }
    }
  }
  return { enviados, errores };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const body = await req.json().catch(() => ({}));
    if (body.test) {
      const jwt = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
      const { data, error } = await admin.auth.getUser(jwt);
      if (error || !data.user?.email) return json({ error: "No autorizado" }, 401);
      await enviar(data.user.email, "Correo de prueba de LicitaControl", plantilla("Los avisos funcionan", "Si lees esto, LicitaControl ya puede enviarte avisos a este correo."));
      return json({ ok: true });
    }
    if (!CRON_SECRET || req.headers.get("x-cron-secret") !== CRON_SECRET) return json({ error: "No autorizado" }, 401);
    return json(await procesar());
  } catch (e) {
    console.error(e);
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});

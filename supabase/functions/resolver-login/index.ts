// Edge Function: resolver-login
// Traduce un teléfono de usuario a su correo de acceso en Supabase Auth.
// PÚBLICA: la llama la app antes del login cuando el usuario escribe
// su teléfono en vez de su correo. Devuelve solo el email, nunca datos extra.
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const soloDigitos = (s: string) => s.replace(/\D/g, "");
const ultimos9 = (s: string) => soloDigitos(s).slice(-9);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Método no permitido" }, 405);

  try {
    const { input } = await req.json();
    const valor = String(input ?? "").trim();
    if (!valor) return json({ email: null });

    // Si ya es un correo, se devuelve tal cual (minúsculas).
    if (valor.includes("@")) {
      return json({ email: valor.toLowerCase() });
    }

    const digitos = soloDigitos(valor);
    if (digitos.length < 6) return json({ email: null });
    const clave = ultimos9(valor);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Busca perfiles cuyo teléfono coincida en los últimos 9 dígitos
    // (tolera +51, espacios, guiones, etc.).
    const { data: perfiles, error } = await supabase
      .from("perfiles")
      .select("id, telefono")
      .ilike("telefono", `%${clave}%`);

    if (error) throw error;

    const coinciden = (perfiles ?? []).filter((p) => {
      const t = ultimos9(String(p.telefono ?? ""));
      return t.length >= 9 && (t === clave || clave.endsWith(t) || t.endsWith(clave));
    });

    // Usuarios distintos que coinciden.
    const ids = [...new Set(coinciden.map((p) => p.id as string))];
    if (ids.length === 0) return json({ email: null });
    if (ids.length > 1) return json({ email: null, ambiguo: true });

    const { data: authData, error: errAuth } =
      await supabase.auth.admin.getUserById(ids[0]);
    if (errAuth || !authData.user?.email) return json({ email: null });

    return json({ email: authData.user.email.toLowerCase() });
  } catch (e) {
    console.error("resolver-login error:", e);
    return json({ email: null });
  }
});

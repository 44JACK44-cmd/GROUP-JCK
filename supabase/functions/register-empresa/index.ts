// Edge Function: register-empresa
// Registra una nueva empresa + su administrador principal.
// Es PÚBLICA (la llama la app sin sesión). Usa service role internamente.
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

function slugify(text: string): string {
  return text
    .toLowerCase()
    .normalize("NFD").replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 40) || "empresa";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Método no permitido" }, 405);

  try {
    const { nombreEmpresa, nombreAdmin, telefono, correo, password } =
      await req.json();

    // ---------- Validaciones ----------
    if (!nombreEmpresa?.trim() || !nombreAdmin?.trim() || !telefono?.trim() ||
        !correo?.trim() || !password) {
      return json({ error: "Completa todos los campos." }, 400);
    }
    const email = correo.trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return json({ error: "El correo no es válido." }, 400);
    }
    if (password.length < 6) {
      return json({ error: "La contraseña debe tener al menos 6 caracteres." }, 400);
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const slug = slugify(nombreEmpresa);

    // ---------- Duplicados ----------
    const { data: existeEmpresa } = await supabase
      .from("empresas")
      .select("id")
      .or(`slug.eq.${slug},nombre.ilike.${nombreEmpresa.trim()}`)
      .maybeSingle();
    if (existeEmpresa) {
      return json({ error: "Esta empresa ya está registrada." }, 409);
    }

    // ---------- 1. Crear empresa ----------
    const { data: empresa, error: errEmpresa } = await supabase
      .from("empresas")
      .insert({ nombre: nombreEmpresa.trim(), slug })
      .select("id")
      .single();
    if (errEmpresa) throw errEmpresa;

    // ---------- 2. Crear usuario admin en Auth ----------
    const { data: authData, error: errAuth } = await supabase.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { nombre: nombreAdmin.trim() },
    });

    if (errAuth || !authData.user) {
      await supabase.from("empresas").delete().eq("id", empresa.id); // rollback
      const msg = (errAuth?.message ?? "").toLowerCase();
      if (msg.includes("already") || msg.includes("registered") || msg.includes("exists")) {
        return json({ error: "El correo ya está asociado a una cuenta." }, 409);
      }
      return json({ error: "No pudimos crear la cuenta. Inténtalo de nuevo." }, 400);
    }

    // ---------- 3. Crear perfil ADMIN ----------
    const { error: errPerfil } = await supabase.from("perfiles").insert({
      id: authData.user.id,
      empresa_id: empresa.id,
      nombre: nombreAdmin.trim(),
      telefono: telefono.trim(),
      rol: "ADMIN",
    });

    if (errPerfil) {
      await supabase.auth.admin.deleteUser(authData.user.id);
      await supabase.from("empresas").delete().eq("id", empresa.id);
      if (errPerfil.message?.includes("duplicate")) {
        return json({ error: "Ese teléfono ya está registrado en otra empresa." }, 409);
      }
      return json({ error: "No pudimos completar el registro. Inténtalo de nuevo." }, 500);
    }

    return json({ ok: true, empresa: nombreEmpresa.trim() });
  } catch (e) {
    console.error("register-empresa error:", e);
    return json({ error: "Ocurrió un error inesperado. Inténtalo de nuevo." }, 500);
  }
});

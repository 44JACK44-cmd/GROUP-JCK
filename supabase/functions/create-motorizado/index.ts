// Edge Function: create-motorizado
// Solo un ADMIN puede crear motorizados EN SU PROPIA empresa.
// El empresa_id se toma del perfil del admin en el servidor (nunca del request).
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

function serviceClient() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Método no permitido" }, 405);

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Sesión requerida." }, 401);

    const supabase = serviceClient();

    // ---------- Identidad del que llama ----------
    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: errUser } = await supabase.auth.getUser(token);
    if (errUser || !user) return json({ error: "Sesión inválida o expirada." }, 401);

    const { data: perfilAdmin, error: errPerfil } = await supabase
      .from("perfiles")
      .select("id, empresa_id, rol, activo")
      .eq("id", user.id)
      .single();

    if (errPerfil || !perfilAdmin?.activo || perfilAdmin.rol !== "ADMIN") {
      return json({ error: "Solo un administrador puede agregar motorizados." }, 403);
    }

    // ---------- Datos ----------
    const { nombre, telefono, correo, password, vehiculoId } = await req.json();

    if (!nombre?.trim() || !telefono?.trim() || !password) {
      return json({ error: "Completa nombre, teléfono y contraseña." }, 400);
    }
    if (password.length < 6) {
      return json({ error: "La contraseña debe tener al menos 6 caracteres." }, 400);
    }

    // Correo explícito o convención teléfono → <tel>@grupojck.app
    let email = correo?.trim().toLowerCase();
    if (!email) {
      const digits = telefono.replace(/\D/g, "");
      if (!digits) return json({ error: "El teléfono no es válido." }, 400);
      email = `${digits}@grupojck.app`;
    } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return json({ error: "El correo no es válido." }, 400);
    }

    // ---------- Crear usuario Auth ----------
    const { data: authData, error: errAuth } = await supabase.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { nombre: nombre.trim() },
    });

    if (errAuth || !authData.user) {
      const msg = (errAuth?.message ?? "").toLowerCase();
      if (msg.includes("already") || msg.includes("registered") || msg.includes("exists")) {
        return json({ error: "Ese correo o teléfono ya está registrado." }, 409);
      }
      return json({ error: "No pudimos crear el usuario. Inténtalo de nuevo." }, 400);
    }

    // ---------- Crear perfil MOTORIZADO en la empresa del admin ----------
    const { error: errPerfil2 } = await supabase.from("perfiles").insert({
      id: authData.user.id,
      empresa_id: perfilAdmin.empresa_id, // ← del servidor, no del request
      nombre: nombre.trim(),
      telefono: telefono.trim(),
      rol: "MOTORIZADO",
    });

    if (errPerfil2) {
      await supabase.auth.admin.deleteUser(authData.user.id);
      if (errPerfil2.message?.includes("duplicate")) {
        return json({ error: "Ese teléfono ya está registrado en tu empresa." }, 409);
      }
      return json({ error: "No pudimos completar el registro." }, 500);
    }

    // ---------- Asignar vehículo (si se indicó y es de la misma empresa) ----------
    if (vehiculoId) {
      const { data: veh } = await supabase
        .from("vehiculos")
        .select("id")
        .eq("id", vehiculoId)
        .eq("empresa_id", perfilAdmin.empresa_id)
        .maybeSingle();

      if (veh) {
        await supabase
          .from("vehiculos")
          .update({ repartidor_id: authData.user.id })
          .eq("id", vehiculoId);
      }
    }

    return json({ ok: true, usuarioId: authData.user.id });
  } catch (e) {
    console.error("create-motorizado error:", e);
    return json({ error: "Ocurrió un error inesperado. Inténtalo de nuevo." }, 500);
  }
});

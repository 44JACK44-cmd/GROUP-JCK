// Edge Function: update-motorizado
// ADMIN edita motorizados de su empresa: datos, vehículo, estado, contraseña.
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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Método no permitido" }, 405);

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Sesión requerida." }, 401);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: errUser } = await supabase.auth.getUser(token);
    if (errUser || !user) return json({ error: "Sesión inválida o expirada." }, 401);

    const { data: admin } = await supabase
      .from("perfiles").select("empresa_id, rol, activo")
      .eq("id", user.id).single();
    if (!admin?.activo || admin.rol !== "ADMIN") {
      return json({ error: "Solo un administrador puede editar motorizados." }, 403);
    }

    const { usuarioId, nombre, telefono, activo, vehiculoId, nuevaPassword } =
      await req.json();
    if (!usuarioId) return json({ error: "Falta el motorizado." }, 400);

    // El motorizado debe pertenecer a la MISMA empresa
    const { data: mot } = await supabase
      .from("perfiles").select("id, empresa_id, rol")
      .eq("id", usuarioId).single();

    if (!mot || mot.empresa_id !== admin.empresa_id || mot.rol !== "MOTORIZADO") {
      return json({ error: "Motorizado no encontrado en tu empresa." }, 404);
    }

    const cambiosPerfil: Record<string, unknown> = {};
    if (nombre?.trim()) cambiosPerfil.nombre = nombre.trim();
    if (telefono?.trim()) cambiosPerfil.telefono = telefono.trim();
    if (activo !== undefined) cambiosPerfil.activo = activo;

    if (Object.keys(cambiosPerfil).length > 0) {
      const { error } = await supabase
        .from("perfiles").update(cambiosPerfil).eq("id", usuarioId);
      if (error) return json({ error: "No pudimos actualizar el motorizado." }, 500);
    }

    // Vehículo: asignar (id) o desasignar (null explícito viene como "__none__")
    if (vehiculoId !== undefined) {
      if (vehiculoId === null || vehiculoId === "") {
        await supabase.from("vehiculos")
          .update({ repartidor_id: null })
          .eq("repartidor_id", usuarioId)
          .eq("empresa_id", admin.empresa_id);
      } else {
        const { data: veh } = await supabase.from("vehiculos")
          .select("id").eq("id", vehiculoId)
          .eq("empresa_id", admin.empresa_id).maybeSingle();
        if (!veh) return json({ error: "El vehículo no pertenece a tu empresa." }, 400);
        await supabase.from("vehiculos")
          .update({ repartidor_id: usuarioId }).eq("id", vehiculoId);
      }
    }

    if (nuevaPassword && nuevaPassword.length >= 6) {
      await supabase.auth.admin.updateUserById(usuarioId, { password: nuevaPassword });
    }

    return json({ ok: true });
  } catch (e) {
    console.error("update-motorizado error:", e);
    return json({ error: "Ocurrió un error inesperado. Inténtalo de nuevo." }, 500);
  }
});

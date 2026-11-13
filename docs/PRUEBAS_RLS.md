# Pruebas de aislamiento multi-tenant (RLS)

Objetivo: demostrar que un usuario de la Empresa A no puede leer ni escribir
datos de la Empresa B, aunque manipule las peticiones.

## Preparación (una sola vez)

### 1. Crear la Empresa B ("Grupo Choke") y su admin

En Supabase **Authentication → Users → Add user** (Auto Confirm User):

- Email: `admin@choke.gas.app` — Password: `choke123`

Luego en **SQL Editor**:

```sql
-- Empresa B
insert into public.empresas (nombre, slug)
values ('Grupo Choke', 'grupo-choke')
on conflict (nombre) do nothing;

-- Perfil admin de la empresa B
insert into public.perfiles (id, empresa_id, nombre, telefono, rol)
select u.id, e.id, 'Admin Choke', '888777666', 'ADMIN'
from auth.users u
cross join public.empresas e
where u.email = 'admin@choke.gas.app' and e.slug = 'grupo-choke'
on conflict (id) do nothing;

-- Un cliente y un producto de prueba en cada empresa
insert into public.clientes (empresa_id, nombre, telefono)
select e.id, 'Cliente Gas', '111'
from public.empresas e where e.slug = 'group-jck';

insert into public.clientes (empresa_id, nombre, telefono)
select e.id, 'Cliente Choke', '222'
from public.empresas e where e.slug = 'grupo-choke';
```

### 2. Obtener tokens JWT de cada admin

```powershell
$ANON = "TU_ANON_KEY"
$URL  = "https://kzhvutzkggcgrnalpcqs.supabase.co"

# Token admin Grupo JCK
'{"email":"admin@grupojck.app","password":"admin123"}' | Out-File -Encoding ascii l1.json
$TOK_A = (curl.exe -s -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" -d "@l1.json" | ConvertFrom-Json).access_token

# Token admin Grupo Choke
'{"email":"admin@choke.gas.app","password":"choke123"}' | Out-File -Encoding ascii l2.json
$TOK_B = (curl.exe -s -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" -d "@l2.json" | ConvertFrom-Json).access_token
```

## Pruebas

### T1 — Cada admin solo ve SUS clientes

```powershell
# Debe devolver SOLO "Cliente Gas"
curl.exe -s "$URL/rest/v1/clientes?select=nombre" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_A"

# Debe devolver SOLO "Cliente Choke"
curl.exe -s "$URL/rest/v1/clientes?select=nombre" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_B"
```

✅ Esperado: A ve 1 fila (Cliente Gas), B ve 1 fila (Cliente Choke). Jamás datos cruzados.

### T2 — Intentar leer clientes ajenos forzando empresa_id

```powershell
# Aunque pida filtrar por la empresa B, RLS devuelve vacío
curl.exe -s "$URL/rest/v1/clientes?select=nombre&empresa_id=eq.<ID_EMPRESA_B>" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_A"
```

✅ Esperado: `[]` — RLS ignora el filtro y aplica el del usuario.

### T3 — Intentar INSERT con empresa_id ajeno (debe FALLAR)

```powershell
# Token de A intenta crear cliente "hacker" en empresa B
curl.exe -s -X POST "$URL/rest/v1/clientes" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_A" -H "Content-Type: application/json" -d '{"empresa_id":"<ID_EMPRESA_B>","nombre":"Intruso"}'
```

✅ Esperado: error `42501` / "new row violates row-level security policy".
La fila NO se crea.

### T4 — Repartidor solo ve SUS pedidos

```powershell
# Login motorizado 999888777 (empresa JCK)
'{"email":"999888777@grupojck.app","password":"demo123"}' | Out-File -Encoding ascii l3.json
$TOK_M = (curl.exe -s -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" -d "@l3.json" | ConvertFrom-Json).access_token

# Solo pedidos donde repartidor_id = él  (o sin asignar de su empresa)
curl.exe -s "$URL/rest/v1/pedidos?select=numero,estado" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_M"
```

### T5 — Motorizado NO puede crear clientes ni gestionar motorizados

```powershell
# Debe FALLAR (403/RLS)
curl.exe -s -X POST "$URL/rest/v1/clientes" -H "apikey: $ANON" -H "Authorization: Bearer $TOK_M" -H "Content-Type: application/json" -d '{"empresa_id":"<ID_EMPRESA_JCK>","nombre":"Hack"}'
```

✅ Esperado: error de permisos.

## Limpieza

```sql
-- Solo si quieres borrar la empresa de prueba:
-- delete from public.empresas where slug = 'grupo-choke';  (cascade manual si aplica)
```

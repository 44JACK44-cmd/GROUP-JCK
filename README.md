# GROUP JCK — App de pedidos y reparto de gas

APK Android (Flutter) + **Supabase** (PostgreSQL + Auth + seguridad por roles).

La app habla **directamente con Supabase**: no necesita servidor propio ni PC encendida.

## Estructura

```
app/           App Flutter (Android) — login, navegación por rol, módulos
docs/          Análisis y documentación por fases
supabase/      schema.sql — base de datos + reglas de seguridad (RLS)
backend/       (legado) API Spring Boot — ya no se usa, se conserva como referencia
mysql/ scripts/ (legado) MySQL local — ya no se usa
```

## Puesta en marcha con Supabase

### 1. Crear el proyecto (solo una vez)

1. Entra a https://supabase.com y crea una cuenta gratis.
2. **New project** → elige nombre `group-jck-gas`, contraseña de DB (guárdala), región más cercana.
3. En **SQL Editor → New query**, pega todo el contenido de `supabase/schema.sql` y ejecuta.
4. En **Authentication → Users → Add user → Create new user** crea dos usuarios
   (marca *Auto Confirm User*):

   | Email | Contraseña | Rol |
   |---|---|---|
   | admin@grupojck.app | admin123 | ADMINISTRADOR |
   | repartidor@grupojck.app | demo123 | REPARTIDOR |

   > El usuario de la app escribe su **teléfono** (ej. `999888777`) y la app lo
   > convierte en `999888777@grupojck.app`. Para el admin de prueba se usa
   > `admin@grupojck.app` — también puedes entrar escribiendo `admin`.

5. En **Project Settings → API** copia la **Project URL** y la **anon public key**
   (o *publishable key*).

### 2. Ejecutar la app

```powershell
cd app
flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co `
            --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
```

Para compilar la APK final:

```powershell
flutter build apk --release `
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
```

La APK resultante funciona en cualquier teléfono con internet, sin depender
 de ninguna PC.

## Credenciales de prueba

| Usuario app | Correo interno | Clave | Rol |
|---|---|---|---|
| admin | admin@grupojck.app | admin123 | ADMINISTRADOR |
| 999888777 (teléfono) | 999888777@grupojck.app | demo123 | REPARTIDOR |

## Seguridad

- Login JWT gestionado por Supabase Auth.
- Row Level Security en todas las tablas:
  - Repartidor solo ve sus pedidos asignados; admin ve todo.
  - Escritura de clientes/productos/precios/caja: solo admin.
  - Entregas, pagos, movimientos de balón y combustible: repartidor registra los suyos.
- La anon key es segura de exponer en la app (RLS protege los datos).

## Estado del proyecto

- **Fase 0**: análisis en `docs/FASE0_ANALISIS.md`
- **Fase 1**: esqueleto migrado a Supabase — schema SQL + login con roles funcionando
- **Fase 2**: Clientes (siguiente)

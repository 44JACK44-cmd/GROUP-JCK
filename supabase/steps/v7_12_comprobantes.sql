-- PASO 12 — Comprobante fotográfico de Yape + columna en pagos
-- Reejecutable y no destructivo.

-- 1) Columna opcional en pagos para la URL del comprobante.
alter table public.pagos
  add column if not exists comprobante_url text;

-- 2) Permiso de subida al bucket "comprobantes" para usuarios autenticados.
--    La lectura es pública (el bucket es público). La subida requiere sesión.
drop policy if exists "comprobantes_insert_auth" on storage.objects;
create policy "comprobantes_insert_auth" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'comprobantes');

drop policy if exists "comprobantes_select_public" on storage.objects;
create policy "comprobantes_select_public" on storage.objects
  for select to public
  using (bucket_id = 'comprobantes');

drop policy if exists "comprobantes_delete_own" on storage.objects;
create policy "comprobantes_delete_own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'comprobantes' and owner = auth.uid());
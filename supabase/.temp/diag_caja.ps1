$ErrorActionPreference = "Continue"
$url = "https://kzhvutzkggcgrnalpcqs.supabase.co"
$key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt6aHZ1dHprZ2djZ3JuYWxwY3FzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQ1Nzg4OTEsImV4cCI6MjExMDE1NDg5MX0.c7RCFTQOrEtT-3D2QjAWEXmUqepx02m5CCsRLyoj_6A"
$body = '{"email":"admin@grupojck.app","password":"admin123"}'
$login = Invoke-RestMethod -Method Post -Uri "$url/auth/v1/token?grant_type=password" -Headers @{apikey=$key} -ContentType "application/json" -Body $body
$tok = $login.access_token
$h = @{ apikey = $key; Authorization = "Bearer $tok"; "Content-Type" = "application/json"; Prefer = "return=representation" }

# Movimiento de caja por referencia (pedido #16 pago)
$pedidoId = "5753e6f5-7921-4215-8321-c1d891e3a252"
$mc = Invoke-RestMethod -Method Get -Uri "$url/rest/v1/movimiento_caja?select=*&referencia_id=eq.$pedidoId" -Headers $h
Write-Output "=== MOVIMIENTO CAJA ==="
$mc | ConvertTo-Json -Depth 5

# Cajas abiertas
$cajas = Invoke-RestMethod -Method Get -Uri "$url/rest/v1/cajas?select=*&empresa_id=eq.e4422e42-824f-4cb2-88c8-abe8f028331d&estado=eq.ABIERTA" -Headers $h
Write-Output "=== CAJAS ABIERTAS ==="
$cajas | ConvertTo-Json -Depth 5

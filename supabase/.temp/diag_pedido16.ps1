$ErrorActionPreference = "Continue"
$url = "https://kzhvutzkggcgrnalpcqs.supabase.co"
$key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt6aHZ1dHprZ2djZ3JuYWxwY3FzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQ1Nzg4OTEsImV4cCI6MjExMDE1NDg5MX0.c7RCFTQOrEtT-3D2QjAWEXmUqepx02m5CCsRLyoj_6A"
$body = '{"email":"admin@grupojck.app","password":"admin123"}'
$login = Invoke-RestMethod -Method Post -Uri "$url/auth/v1/token?grant_type=password" -Headers @{apikey=$key} -ContentType "application/json" -Body $body
$tok = $login.access_token
$h = @{ apikey = $key; Authorization = "Bearer $tok"; "Content-Type" = "application/json"; Prefer = "return=representation" }

$ped = Invoke-RestMethod -Method Get -Uri "$url/rest/v1/pedidos?select=id,numero,estado,repartidor_id,cliente_id,total,fecha&numero=eq.16" -Headers $h
Write-Output "=== PEDIDO #16 ==="
$ped | ConvertTo-Json -Depth 5
$pedidoId = $ped[0].id

$ent = Invoke-RestMethod -Method Get -Uri "$url/rest/v1/entregas?select=*&pedido_id=eq.$pedidoId" -Headers $h
Write-Output "=== ENTREGAS ==="
$ent | ConvertTo-Json -Depth 5

$pag = Invoke-RestMethod -Method Get -Uri "$url/rest/v1/pagos?select=*&pedido_id=eq.$pedidoId" -Headers $h
Write-Output "=== PAGOS ==="
$pag | ConvertTo-Json -Depth 5

$mov = Invoke-RestMethod -Method Get -Uri "$url/rest/v1/movimiento_bal_on?select=*&pedido_id=eq.$pedidoId" -Headers $h
Write-Output "=== MOVIMIENTO BALON ==="
$mov | ConvertTo-Json -Depth 5

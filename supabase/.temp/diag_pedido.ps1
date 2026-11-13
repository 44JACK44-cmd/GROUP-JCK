$ErrorActionPreference = "Continue"
$url = "https://kzhvutzkggcgrnalpcqs.supabase.co"
$key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt6aHZ1dHprZ2djZ3JuYWxwY3FzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQ1Nzg4OTEsImV4cCI6MjExMDE1NDg5MX0.c7RCFTQOrEtT-3D2QjAWEXmUqepx02m5CCsRLyoj_6A"

$body = '{"email":"admin@grupojck.app","password":"admin123"}'
$login = Invoke-RestMethod -Method Post -Uri "$url/auth/v1/token?grant_type=password" -Headers @{apikey=$key} -ContentType "application/json" -Body $body
$tok = $login.access_token
$uid = $login.user.id
Write-Output "=== ADMIN uid: $uid ==="

$h = @{ apikey = $key; Authorization = "Bearer $tok"; "Content-Type" = "application/json"; Prefer = "return=representation" }

function Mostrar($titulo, $r) {
  Write-Output "=== $titulo ==="
  Write-Output ($r | ConvertTo-Json -Depth 6 -Compress)
}

# Perfil del admin
try {
  $perfil = Invoke-RestMethod -Method Get -Uri "$url/rest/v1/perfiles?select=id,nombre,rol,empresa_id&id=eq.$uid" -Headers $h
  Mostrar "PERFIL" $perfil
  $empresaId = $perfil[0].empresa_id
  Write-Output "=== EMPRESA: $empresaId ==="
} catch {
  Write-Output "ERROR PERFIL: $($_.Exception.Message)"
  Write-Output $_.ErrorDetails.Message
}

# Empresa
try {
  $emp = Invoke-RestMethod -Method Get -Uri "$url/rest/v1/empresas?select=id,nombre,slug&id=eq.$empresaId" -Headers $h
  Mostrar "EMPRESA" $emp
} catch {
  Write-Output "ERROR EMPRESA: $($_.Exception.Message)"
}

# Productos
try {
  $prod = Invoke-RestMethod -Method Get -Uri "$url/rest/v1/productos?select=id,nombre,precio_base&empresa_id=eq.$empresaId&limit=5" -Headers $h
  Mostrar "PRODUCTOS" $prod
} catch {
  Write-Output "ERROR PRODUCTOS: $($_.Exception.Message)"
}

# Clientes existentes
try {
  $cli = Invoke-RestMethod -Method Get -Uri "$url/rest/v1/clientes?select=id,nombre,telefono&empresa_id=eq.$empresaId&limit=5" -Headers $h
  Mostrar "CLIENTES" $cli
} catch {
  Write-Output "ERROR CLIENTES: $($_.Exception.Message)"
}

# Intentar crear un cliente de prueba
$cliBody = @{
  empresa_id = $empresaId
  nombre = "Diag Cliente Admin"
  telefono = "900000001"
  direccion = "Av. Diagnostico 1"
  latitud = -16.4090
  longitud = -71.5375
} | ConvertTo-Json -Compress
try {
  $nuevoCli = Invoke-RestMethod -Method Post -Uri "$url/rest/v1/clientes" -Headers $h -Body $cliBody
  Mostrar "CLIENTE CREADO" $nuevoCli
  $clienteId = $nuevoCli[0].id
} catch {
  Write-Output "ERROR CREAR CLIENTE: $($_.Exception.Message)"
  Write-Output $_.ErrorDetails.Message
}

# Intentar crear un pedido (cabecera)
if ($clienteId -and $prod.Count -gt 0) {
  $prodId = $prod[0].id
  $pedidoBody = @{
    empresa_id = $empresaId
    cliente_id = $clienteId
    creado_por = $uid
    total = 45
    uuid_offline = "diag-$(Get-Random)"
    forma_pago = "EFECTIVO"
  } | ConvertTo-Json -Compress
  try {
    $pedido = Invoke-RestMethod -Method Post -Uri "$url/rest/v1/pedidos" -Headers $h -Body $pedidoBody
    Mostrar "PEDIDO CREADO" $pedido
    $pedidoId = $pedido[0].id

    # Detalle con empresa_id
    $detBody = @{
      empresa_id = $empresaId
      pedido_id = $pedidoId
      producto_id = $prodId
      cantidad = 1
      precio_unitario = 45
    } | ConvertTo-Json -Compress
    try {
      $det = Invoke-RestMethod -Method Post -Uri "$url/rest/v1/detalle_pedido" -Headers $h -Body $detBody
      Mostrar "DETALLE CREADO" $det
    } catch {
      Write-Output "ERROR DETALLE: $($_.Exception.Message)"
      Write-Output $_.ErrorDetails.Message
    }

    # Limpieza
    try {
      Invoke-RestMethod -Method Delete -Uri "$url/rest/v1/detalle_pedido?pedido_id=eq.$pedidoId" -Headers $h | Out-Null
      Invoke-RestMethod -Method Delete -Uri "$url/rest/v1/pedidos?id=eq.$pedidoId" -Headers $h | Out-Null
      Invoke-RestMethod -Method Delete -Uri "$url/rest/v1/clientes?id=eq.$clienteId" -Headers $h | Out-Null
      Write-Output "=== LIMPIEZA OK ==="
    } catch {
      Write-Output "ERROR LIMPIEZA: $($_.Exception.Message)"
    }
  } catch {
    Write-Output "ERROR CREAR PEDIDO: $($_.Exception.Message)"
    Write-Output $_.ErrorDetails.Message
  }
}

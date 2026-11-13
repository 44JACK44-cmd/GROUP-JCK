$ErrorActionPreference = "Continue"
$url = "https://kzhvutzkggcgrnalpcqs.supabase.co"
$key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt6aHZ1dHprZ2djZ3JuYWxwY3FzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQ1Nzg4OTEsImV4cCI6MjExMDE1NDg5MX0.c7RCFTQOrEtT-3D2QjAWEXmUqepx02m5CCsRLyoj_6A"
$body = '{"email":"admin@grupojck.app","password":"admin123"}'
$login = Invoke-RestMethod -Method Post -Uri "$url/auth/v1/token?grant_type=password" -Headers @{apikey=$key} -ContentType "application/json" -Body $body
$tok = $login.access_token
$h = @{ apikey = $key; Authorization = "Bearer $tok"; "Content-Type" = "application/json"; Prefer = "return=representation" }

# Verificar versión actual
$ver = Invoke-RestMethod -Method Get -Uri "$url/rest/v1/app_versiones?select=*" -Headers $h
Write-Output "=== VERSION ACTUAL ==="
$ver | ConvertTo-Json -Depth 5

# Actualizar versión
$updateBody = @{
  version_code = 5
  version_name = "1.0.5"
  apk_url = "https://github.com/44JACK44-cmd/GROUP-JCK/releases/download/v1.0.5/app-release.apk"
  notas = "Actualizacion: cuaderno digital, mapas, zonas de reparto, rendicion consolidada, conciliacion diaria"
  obligatoria = $false
} | ConvertTo-Json -Compress

try {
  $r = Invoke-RestMethod -Method Patch -Uri "$url/rest/v1/app_versiones?id=eq.1" -Headers $h -Body $updateBody
  Write-Output "=== VERSION ACTUALIZADA ==="
  $r | ConvertTo-Json -Depth 5
} catch {
  Write-Output "ERROR: $($_.Exception.Message)"
  Write-Output $_.ErrorDetails.Message
  # Intentar insert si no existe
  try {
    $insertBody = @{
      id = 1
      version_code = 5
      version_name = "1.0.5"
      apk_url = "https://github.com/44JACK44-cmd/GROUP-JCK/releases/download/v1.0.5/app-release.apk"
      notas = "Actualizacion: cuaderno digital, mapas, zonas de reparto, rendicion consolidada, conciliacion diaria"
      obligatoria = $false
    } | ConvertTo-Json -Compress
    $r2 = Invoke-RestMethod -Method Post -Uri "$url/rest/v1/app_versiones" -Headers $h -Body $insertBody
    Write-Output "=== VERSION INSERTADA ==="
    $r2 | ConvertTo-Json -Depth 5
  } catch {
    Write-Output "ERROR INSERT: $($_.Exception.Message)"
    Write-Output $_.ErrorDetails.Message
  }
}

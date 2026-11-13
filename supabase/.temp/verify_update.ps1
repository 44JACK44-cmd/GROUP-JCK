$ErrorActionPreference = "Continue"
$url = "https://kzhvutzkggcgrnalpcqs.supabase.co"
$anon = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt6aHZ1dHprZ2djZ3JuYWxwY3FzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQ1Nzg4OTEsImV4cCI6MjExMDE1NDg5MX0.c7RCFTQOrEtT-3D2QjAWEXmUqepx02m5CCsRLyoj_6A"

Write-Output "=== app_versiones (como la lee la app) ==="
$r = Invoke-RestMethod -Method Get -Uri "$url/rest/v1/app_versiones?select=version_code,version_name,apk_url,notas&id=eq.1" -Headers @{apikey=$anon; Authorization="Bearer $anon"}
$r | ConvertTo-Json -Depth 4

Write-Output "=== Simulacion de comparacion en el telefono ==="
# APKs antiguas posibles en el telefono (split-per-abi)
foreach ($local in @(2004, 2005, 2006, 4, 5, 6)) {
  $vieja = $r.version_code -gt $local          # logica ANTIGUA (compilada en APKs viejas)
  $nueva = ($r.version_code % 1000) -gt ($local % 1000)  # logica NUEVA (fix)
  Write-Output ("telefono versionCode={0,-5} | APK vieja muestra update: {1,-5} | APK nueva muestra update: {2}" -f $local, $vieja, $nueva)
}

Write-Output "=== APK app-v7.apk descargable? ==="
$head = curl.exe -s -I -L "$($r.apk_url)" -H "apikey: $anon"
$head | Select-String -Pattern "HTTP/|content-length|content-type"

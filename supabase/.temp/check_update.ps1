$ErrorActionPreference = "Continue"
$url = "https://kzhvutzkggcgrnalpcqs.supabase.co"
$anon = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt6aHZ1dHprZ2djZ3JuYWxwY3FzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQ1Nzg4OTEsImV4cCI6MjExMDE1NDg5MX0.c7RCFTQOrEtT-3D2QjAWEXmUqepx02m5CCsRLyoj_6A"

Write-Output "=== 1. LECTURA CON ANON KEY (como lo hace la app) ==="
try {
  $r = Invoke-RestMethod -Method Get -Uri "$url/rest/v1/app_versiones?select=*&id=eq.1" -Headers @{apikey=$anon; Authorization="Bearer $anon"}
  $r | ConvertTo-Json -Depth 5
} catch {
  Write-Output "ERROR LECTURA: $($_.Exception.Message)"
  if ($_.Exception.Response) {
    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
    Write-Output "RESPONSE: $($reader.ReadToEnd())"
  }
}

Write-Output "=== 2. VERIFICAR APK EN STORAGE ==="
$apkUrl = "$url/storage/v1/object/public/releases/app-v6.apk"
try {
  $head = Invoke-WebRequest -Method Head -Uri $apkUrl -Headers @{apikey=$anon}
  Write-Output "app-v6.apk: STATUS=$($head.StatusCode) SIZE=$($head.Headers['Content-Length'])"
} catch {
  Write-Output "app-v6.apk NO EXISTE o no es publico: $($_.Exception.Message)"
}

# Ver tambien los otros
foreach ($n in @("app-v5.apk","app-v4.apk")) {
  try {
    $h = Invoke-WebRequest -Method Head -Uri "$url/storage/v1/object/public/releases/$n" -Headers @{apikey=$anon}
    Write-Output "$n : STATUS=$($h.StatusCode) SIZE=$($h.Headers['Content-Length'])"
  } catch {
    Write-Output "$n : NO EXISTE"
  }
}

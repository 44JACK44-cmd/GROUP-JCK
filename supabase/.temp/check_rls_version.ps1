$ErrorActionPreference = "Continue"
$url = "https://kzhvutzkggcgrnalpcqs.supabase.co"
$anon = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt6aHZ1dHprZ2djZ3JuYWxwY3FzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQ1Nzg4OTEsImV4cCI6MjExMDE1NDg5MX0.c7RCFTQOrEtT-3D2QjAWEXmUqepx02m5CCsRLyoj_6A"

Write-Output "=== A) LECTURA ANON (sin sesion) ==="
try {
  $r = Invoke-RestMethod -Method Get -Uri "$url/rest/v1/app_versiones?select=version_code,id&id=eq.1" -Headers @{apikey=$anon; Authorization="Bearer $anon"}
  Write-Output ("OK anon: version_code=" + $r.version_code)
} catch { Write-Output "FAIL anon: $($_.Exception.Message)" }

Write-Output "=== B) LOGIN ADMIN ==="
$body = '{"email":"admin@grupojck.app","password":"admin123"}'
try {
  $login = Invoke-RestMethod -Method Post -Uri "$url/auth/v1/token?grant_type=password" -Headers @{apikey=$anon} -ContentType "application/json" -Body $body
  $tok = $login.access_token
  Write-Output "login OK, role del JWT=authenticated"
} catch { Write-Output "FAIL login: $($_.Exception.Message)"; exit 1 }

Write-Output "=== C) LECTURA AUTHENTICADO (como la app con sesion) ==="
try {
  $r2 = Invoke-RestMethod -Method Get -Uri "$url/rest/v1/app_versiones?select=version_code,id&id=eq.1" -Headers @{apikey=$anon; Authorization="Bearer $tok"}
  Write-Output ("OK auth: version_code=" + $r2.version_code)
} catch {
  Write-Output "FAIL auth: $($_.Exception.Message)"
  if ($_.Exception.Response) {
    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
    Write-Output "RESPONSE: $($reader.ReadToEnd())"
  }
}

# ============================================================
# Publicar actualización OTA de GasApp
#
# Uso:
#   .\publicar-update.ps1 -VersionCode 2 -Notas "Corrección de pedidos"
#
# Requisito (una sola vez): crear scripts\secrets.ps1 con:
#   $env:SUPABASE_URL = "https://kzhvutzkggcgrnalpcqs.supabase.co"
#   $env:SUPABASE_SERVICE_KEY = "eyJ...service_role..."
# (la service key está en Supabase → Settings → API Keys)
# ============================================================
param(
  [Parameter(Mandatory=$true)][int]$VersionCode,
  [string]$VersionName = "",
  [string]$Notas = "",
  [switch]$Obligatoria
)

$ErrorActionPreference = "Stop"
$root = "G:\misProyectos\GROUP JCK"
$appDir = "$root\app"
$apkOut = "$appDir\build\app\outputs\flutter-apk"

# --- Credenciales ---
if (Test-Path "$root\scripts\secrets.ps1") { . "$root\scripts\secrets.ps1" }
if (-not $env:SUPABASE_URL -or -not $env:SUPABASE_SERVICE_KEY) {
  Write-Error "Faltan credenciales. Crea scripts\secrets.ps1 (ver encabezado del script)."
  exit 1
}
$bucket = "releases"
$apkName = "app-v$VersionCode.apk"
$apkPath = "$apkOut\app-arm64-v8a-release.apk"

Write-Host "== 1/4 Actualizando versión en pubspec ==" -ForegroundColor Cyan
$pubspec = "$appDir\pubspec.yaml"
$content = Get-Content $pubspec -Raw
$newVer = if ($VersionName) { "1.0.$VersionCode" } else { "1.0.$VersionCode" }
# version: X.Y.Z+BUILD → build number = VersionCode
$content = $content -replace 'version: \d+\.\d+\.\d+\+\d+', "version: $newVer+$VersionCode"
Set-Content $pubspec $content -NoNewline
Write-Host "   version: $newVer+$VersionCode"

Write-Host "== 2/4 Compilando APK (arm64) ==" -ForegroundColor Cyan
Push-Location $appDir
flutter build apk --release --split-per-abi --target-platform android-arm64
if ($LASTEXITCODE -ne 0) { Pop-Location; Write-Error "Falló la compilación"; exit 1 }
Pop-Location

if (-not (Test-Path $apkPath)) { Write-Error "No se generó $apkPath"; exit 1 }

Write-Host "== 3/4 Subiendo APK a Supabase Storage ==" -ForegroundColor Cyan
curl.exe -s -X POST "$env:SUPABASE_URL/storage/v1/object/$bucket/$apkName" `
  -H "apikey: $env:SUPABASE_SERVICE_KEY" `
  -H "Authorization: Bearer $env:SUPABASE_SERVICE_KEY" `
  -H "Content-Type: application/vnd.android.package-archive" `
  -H "x-upsert: true" `
  --data-binary "@$apkPath"
Write-Host ""

Write-Host "== 4/4 Actualizando app_versiones ==" -ForegroundColor Cyan
$apkUrl = "$env:SUPABASE_URL/storage/v1/object/public/$bucket/$apkName"
$body = @{
  id = 1
  version_code = $VersionCode
  version_name = $newVer
  apk_url = $apkUrl
  notas = $Notas
  obligatoria = [bool]$Obligatoria
  actualizado_en = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
} | ConvertTo-Json
$tmp = "$env:TEMP\ver.json"
$body | Out-File -Encoding ascii $tmp
curl.exe -s -X POST "$env:SUPABASE_URL/rest/v1/app_versiones" `
  -H "apikey: $env:SUPABASE_SERVICE_KEY" `
  -H "Authorization: Bearer $env:SUPABASE_SERVICE_KEY" `
  -H "Content-Type: application/json" `
  -H "Prefer: resolution=merge-duplicates" `
  -d "@$tmp"

Write-Host ""
Write-Host "== LISTO ==" -ForegroundColor Green
Write-Host "Versión $newVer+$VersionCode publicada."
Write-Host "Los usuarios verán el aviso de actualización al abrir la app."

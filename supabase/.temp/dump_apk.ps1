$ErrorActionPreference = "SilentlyContinue"
$sdk = "$env:LOCALAPPDATA\Android\Sdk"
Write-Output "SDK: $sdk"

# Find aapt2
$aapt = Get-ChildItem -Path "$sdk\build-tools" -Recurse -Filter "aapt2.exe" | Select-Object -First 1
if ($aapt) { Write-Output "aapt2: $($aapt.FullName)" } else { Write-Output "aapt2 NOT FOUND" }

# Dump versionCode from the release APK
$apk = "G:\misProyectos\GROUP JCK\app\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
if ($aapt) {
  Write-Output "=== BADGING (app-arm64-v8a-release.apk) ==="
  & $aapt.FullName dump badging $apk | Select-String -Pattern "package:|sdkVersion|application-label:"
}

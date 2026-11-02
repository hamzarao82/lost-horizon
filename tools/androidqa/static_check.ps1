# Static checks for the Android APK (no device or emulator needed).
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\androidqa\static_check.ps1 [-Apk path]
# Status: RUN on 2026-11-02 against release-assets/LostHorizon-android.apk (see docs/ANDROID_QA.md).
param([string]$Apk = "release-assets\LostHorizon-android.apk")

$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "$env:LOCALAPPDATA\Android\Sdk" }
$bt = Get-ChildItem "$sdk\build-tools" -Directory | Sort-Object Name -Descending | Select-Object -First 1
if (-not $bt) { Write-Error "no build-tools in $sdk"; exit 2 }
$aapt2 = Join-Path $bt.FullName "aapt2.exe"
$apksigner = Join-Path $bt.FullName "apksigner.bat"
$zipalign = Join-Path $bt.FullName "zipalign.exe"
if (-not (Test-Path $Apk)) { Write-Error "APK not found: $Apk"; exit 2 }

$problems = 0
function Check($ok, $msg) { if ($ok) { "ok    $msg" } else { "WARN  $msg"; $script:problems++ } }

"APK: $Apk ({0:N1} MiB), build-tools $($bt.Name)" -f ((Get-Item $Apk).Length / 1MB)
$badging = & $aapt2 dump badging $Apk 2>$null | Out-String
$tree = & $aapt2 dump xmltree --file AndroidManifest.xml $Apk 2>$null | Out-String

Check ($badging -match "package: name='com.hamzarao.losthorizon'") "package id com.hamzarao.losthorizon"
Check ($badging -match "native-code: 'arm64-v8a'" -and $badging -notmatch "armeabi") "native code arm64-v8a only (32-bit phones unsupported)"
Check ($tree -match "minSdkVersion.*=24") "minSdk 24 (Android 7.0)"
Check ($badging -match "uses-gl-es: '0x30000'") "OpenGL ES 3.0 required (Compatibility renderer)"
Check ($badging -notmatch "uses-permission") "no permissions requested"
Check ($tree -match "screenOrientation.*=0\b") "landscape orientation"
Check ($tree -match "allowBackup.*=false") "allowBackup=false"
if ($badging -match "application-debuggable" -or $tree -match "debuggable.*=true") {
    "NOTE  debuggable flag is set: this is a DEBUG build (fine for testing, not for store release)"
}

$sig = & $apksigner verify --verbose $Apk 2>&1 | Out-String
Check ($sig -match "Verifies") "signature verifies"
Check ($sig -match "v2 scheme.*: true") "APK Signature Scheme v2 present"

& $zipalign -c 4 $Apk 2>&1 | Out-Null
Check ($LASTEXITCODE -eq 0) "zipalign 4-byte alignment"

# Size breakdown: anything that is not the engine or the game should not be in the APK.
$list = & unzip -l $Apk 2>$null
if ($list) {
    $junk = ($list | Select-String "assets/portfolio/|assets/site-assets/|assets/docs/|assets/tools/").Count
    Check ($junk -eq 0) "no website, docs or tools files packed in the APK (found $junk)"
    $tests = ($list | Select-String "assets/tests/").Count
    Check ($tests -eq 0) "no test scripts packed in the APK (found $tests)"
}
"`n$problems warning(s)."
exit ([int]($problems -gt 0))

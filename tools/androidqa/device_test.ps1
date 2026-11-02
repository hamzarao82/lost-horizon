# Install the debug APK on a connected phone/emulator, launch it, and collect evidence.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\androidqa\device_test.ps1 [-Seconds 40]
# Status: NOT RUN. No phone was attached and the emulator cannot run on this PC (see docs/ANDROID_QA.md).
#         Only the syntax was checked. Treat the first real run as the test of this script.
param(
    [string]$Apk = "release-assets\LostHorizon-android.apk",
    [int]$Seconds = 40,
    [string]$Out = "androidqa-out"
)
$pkg = "com.hamzarao.losthorizon"
$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "$env:LOCALAPPDATA\Android\Sdk" }
$adb = "$sdk\platform-tools\adb.exe"

$devices = & $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "\tdevice$" }
if (-not $devices) { Write-Error "No device attached. Enable USB debugging and run: adb devices"; exit 2 }
New-Item -ItemType Directory -Force $Out | Out-Null

"Device:"; & $adb shell getprop ro.product.model; & $adb shell getprop ro.build.version.release
& $adb shell getprop ro.product.cpu.abilist
& $adb shell wm size

"Installing..."; & $adb install -r $Apk
if ($LASTEXITCODE -ne 0) { Write-Error "install failed"; exit 3 }

& $adb logcat -c
& $adb shell dumpsys gfxinfo $pkg reset | Out-Null
& $adb shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 | Out-Null
"Running for $Seconds s (play: move, attack, dodge, use the Use/Heal/Tele buttons)..."
Start-Sleep -Seconds $Seconds

& $adb exec-out screencap -p | Set-Content -Encoding Byte "$Out\screen.png"
& $adb logcat -d -s godot:V AndroidRuntime:E DEBUG:F | Set-Content "$Out\logcat_godot.txt"
& $adb logcat -d *:E | Select-String $pkg | Set-Content "$Out\logcat_errors.txt"
& $adb shell dumpsys gfxinfo $pkg | Set-Content "$Out\gfxinfo.txt"
& $adb shell dumpsys meminfo $pkg | Set-Content "$Out\meminfo.txt"
& $adb shell dumpsys SurfaceFlinger --latency | Select-Object -First 5 | Set-Content "$Out\surface_latency.txt"

$crash = (Get-Content "$Out\logcat_godot.txt" | Select-String "FATAL|Fatal signal|AndroidRuntime").Count
"Crash lines: $crash"
Select-String -Path "$Out\gfxinfo.txt" -Pattern "Total frames rendered|Janky frames|50th percentile|90th percentile|99th percentile" | ForEach-Object { $_.Line.Trim() }
Select-String -Path "$Out\meminfo.txt" -Pattern "TOTAL PSS|TOTAL  " | Select-Object -First 2 | ForEach-Object { $_.Line.Trim() }
"Evidence saved in $Out (send screen.png, gfxinfo.txt, meminfo.txt, logcat_godot.txt back)."

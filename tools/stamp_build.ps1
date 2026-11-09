# Writes the current commit and time into scripts/core/build_info.gd so the build can say what it is.
# usage: powershell -ExecutionPolicy Bypass -File tools\stamp_build.ps1   (run before every export)
$root = Split-Path -Parent $PSScriptRoot
$hash = (git -C $root rev-parse --short HEAD).Trim()
$when = Get-Date -Format 'yyyy-MM-dd HH:mm'
$text = @"
class_name BuildInfo
extends RefCounted
## Which build is running, shown in the corner of the main menu. tools/stamp_build.ps1 rewrites LABEL before
## every export (commit and time), so "is this the new version?" can be answered by looking at the menu.
const LABEL: String = "build $hash  |  $when"
"@
Set-Content -Path (Join-Path $root 'scripts\core\build_info.gd') -Value $text -Encoding utf8
Write-Output "Stamped: build $hash | $when"

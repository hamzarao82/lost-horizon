# Records the opening of Lost Horizon as an MP4 story video (Movie Maker, windowed) and encodes it with ffmpeg.
# Usage: powershell -ExecutionPolicy Bypass -File tools/review/record_opening.ps1 [-Worktree <path>] [-Out <mp4>]
param(
	[string]$Worktree = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
	[string]$Out = "C:\Users\SCS\OneDrive\Documents\GitHub\lost-horizon-review-hub\videos\lost-horizon-opening-$(Get-Date -Format yyyy-MM-dd).mp4"
)

$ErrorActionPreference = "Stop"
$godot = "C:\Tools\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe"
$ffmpeg = "C:\Users\SCS\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg.Essentials_Microsoft.Winget.Source_8wekyb3d8bbwe\ffmpeg-9.0.1-essentials_build\bin\ffmpeg.exe"
$scratch = Join-Path $env:TEMP "lh-opening-record"
New-Item -ItemType Directory -Force -Path $scratch | Out-Null
$avi = Join-Path $scratch "opening.avi"
$outDir = Split-Path -Parent $Out
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# One-time asset import (skip if already done in this worktree).
& $godot --headless --path $Worktree --import

# Record. Movie Maker runs the game windowed at a fixed 30 fps; the scene quits itself when the sequence ends.
& $godot --path $Worktree --write-movie $avi --fixed-fps 30 --resolution 1280x720 res://tools/review/record_opening.tscn
if ($LASTEXITCODE -ne 0) { throw "Godot exited with code $LASTEXITCODE" }

# Encode to H.264 + AAC for sharing, then remove the large intermediate AVI.
& $ffmpeg -y -i $avi -c:v libx264 -crf 20 -preset medium -pix_fmt yuv420p -c:a aac -b:a 160k $Out
if ($LASTEXITCODE -ne 0) { throw "ffmpeg exited with code $LASTEXITCODE" }
Remove-Item -Force $avi
Write-Output "Wrote $Out"

<#
.SYNOPSIS
  Packages a Godot web export for hosting with content-hashed file names.

.DESCRIPTION
  GitHub Pages caches files for 10 minutes. After a redeploy, a visitor could get a NEW index.wasm with an
  OLD index.pck (or the reverse) and the game fails to start. This script renames every exported asset to
  index-<hash>.* and patches index.html so the page always asks for a matching set. index.html itself keeps
  its name; the hashed files never collide between versions.

.EXAMPLE
  Godot --headless --path . --export-release "Web" build/web/index.html
  powershell -File tools/package_web.ps1 -Source build/web -Dest site-assets/play
#>
param(
  [Parameter(Mandatory)][string]$Source,
  [Parameter(Mandatory)][string]$Dest
)
$ErrorActionPreference = 'Stop'
$Source = (Resolve-Path $Source).Path
New-Item -ItemType Directory -Force $Dest | Out-Null
$Dest = (Resolve-Path $Dest).Path

foreach ($need in 'index.html', 'index.js', 'index.wasm', 'index.pck') {
  if (-not (Test-Path (Join-Path $Source $need))) { throw "Missing $need in $Source (export the Web preset first)." }
}

# Hash of the three files that define a build.
$sha = [System.Security.Cryptography.SHA256]::Create()
foreach ($n in 'index.js', 'index.wasm', 'index.pck') {
  $chunk = [IO.File]::ReadAllBytes((Join-Path $Source $n))
  [void]$sha.TransformBlock($chunk, 0, $chunk.Length, $null, 0)
}
[void]$sha.TransformFinalBlock([byte[]]@(), 0, 0)
$hash = (($sha.Hash | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 8)
$name = "index-$hash"

# Remove the previous packaged set (only files we own: index.html and index*.* assets).
Get-ChildItem $Dest -File | Where-Object { $_.Name -like 'index*' } | Remove-Item -Force

foreach ($f in Get-ChildItem $Source -File) {
  if ($f.Name -eq 'index.html') { continue }
  if ($f.Name -like '*.import') { continue }   # Godot editor files, not part of the export
  if ($f.Name -notlike 'index.*') { Copy-Item $f.FullName $Dest; continue }
  $newName = $name + $f.Name.Substring('index'.Length)
  Copy-Item $f.FullName (Join-Path $Dest $newName)
}

$html = Get-Content (Join-Path $Source 'index.html') -Raw
$html = $html -replace '"executable"\s*:\s*"index"', ('"executable":"' + $name + '"')
$html = [regex]::Replace($html, '(?<![\w-])index\.(js|wasm|pck|png|icon\.png|apple-touch-icon\.png)', ($name + '.$1'))
Set-Content -Path (Join-Path $Dest 'index.html') -Value $html -NoNewline -Encoding UTF8

$size = (Get-ChildItem $Dest -File | Measure-Object Length -Sum).Sum / 1MB
"Packaged build $name -> $Dest ({0:N1} MB)" -f $size

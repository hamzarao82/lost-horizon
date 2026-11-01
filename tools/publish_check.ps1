<#
.SYNOPSIS
  Read-only pre-publish check for the Lost Horizon repo. Changes nothing.
.DESCRIPTION
  Looks at every file git would include (tracked files plus untracked files that are not ignored) and reports:
    ERROR  secrets or signing material, files over 90 MB, missing .gitignore entries, missing licence files
    WARN   build output that is tracked, files over 50 MB, LFS-pattern files without git-lfs, no remote
  Exits 1 if any ERROR is found, otherwise 0.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\publish_check.ps1
#>
[CmdletBinding()]
param(
    [string]$Root = "",
    [int]$MaxMB = 90,
    [int]$WarnMB = 50
)

$ErrorActionPreference = "Stop"
if (-not $Root) {
    $here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $Root = (Resolve-Path (Join-Path $here "..")).Path
}
Set-Location $Root
$errors = New-Object System.Collections.Generic.List[string]
$warns = New-Object System.Collections.Generic.List[string]
function Err([string]$m)  { $script:errors.Add($m); Write-Host "ERROR  $m" -ForegroundColor Red }
function Warn([string]$m) { $script:warns.Add($m);  Write-Host "WARN   $m" -ForegroundColor Yellow }
function Ok([string]$m)   { Write-Host "ok     $m" -ForegroundColor Green }

if (-not (Test-Path ".git")) { Err "not a git repository: $Root"; exit 1 }

# Everything that would be committed: tracked + untracked-but-not-ignored.
$files = @(git ls-files -co --exclude-standard) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }
Write-Host "Checking $($files.Count) files that git would publish...`n"

# 1. Signing material and secret-looking files.
$badNames = '(^|/)(debug\.keystore|.*\.keystore|.*\.jks|.*\.p12|.*\.pfx|.*\.pem|.*\.key|\.env(\..*)?|id_rsa.*|.*\.mobileprovision|export_credentials\.cfg)$'
$hits = $files | Where-Object { $_ -match $badNames }
if ($hits) { $hits | ForEach-Object { Err "signing/secret file would be published: $_" } } else { Ok "no keystores, private keys or .env files" }

# 2. Token patterns inside text files (skip big and binary files).
$textExt = '\.(gd|tscn|tres|godot|cfg|json|md|txt|yml|yaml|ps1|sh|ts|tsx|js|mjs|css|html|toml|import)$'
$patterns = @(
    'gh[pousr]_[A-Za-z0-9]{30,}',
    'github_pat_[A-Za-z0-9_]{40,}',
    'AKIA[0-9A-Z]{16}',
    '-----BEGIN [A-Z ]*PRIVATE KEY-----',
    'xox[baprs]-[A-Za-z0-9-]{10,}',
    '(?i)(api[_-]?key|secret|password)\s*[:=]\s*["''][^"'']{12,}["'']'
)
$leaks = 0
foreach ($f in $files) {
    if ($f -notmatch $textExt) { continue }
    if ((Get-Item -LiteralPath $f).Length -gt 2MB) { continue }
    foreach ($p in $patterns) {
        $m = Select-String -LiteralPath $f -Pattern $p -List -ErrorAction SilentlyContinue
        if ($m) { Err "possible secret in ${f}:$($m.LineNumber) (pattern $p)"; $leaks++ }
    }
}
if ($leaks -eq 0) { Ok "no token or private-key patterns in text files" }

# 3. File sizes.
$big = 0
foreach ($f in $files) {
    $mb = (Get-Item -LiteralPath $f).Length / 1MB
    if ($mb -gt $MaxMB) { Err ("{0:N1} MB exceeds {1} MB (GitHub rejects files over 100 MB): {2}" -f $mb, $MaxMB, $f); $big++ }
    elseif ($mb -gt $WarnMB) { Warn ("{0:N1} MB is large: {1}" -f $mb, $f); $big++ }
}
if ($big -eq 0) { Ok "no file over $WarnMB MB" }

# 4. Build output.
$build = $files | Where-Object { $_ -match '^(build|\.godot|\.export|portfolio/(node_modules|\.next|out))/' }
if ($build) { Warn "build/cache output would be published ($($build.Count) files), for example: $((($build | Select-Object -First 3) -join ', '))" } else { Ok "no build or cache folders in the file list" }
$play = Test-Path "site-assets/play/index.html"
if ($play) {
    $mb = [math]::Round(((Get-ChildItem "site-assets/play" -Recurse -File | Measure-Object Length -Sum).Sum / 1MB), 1)
    Ok "site-assets/play found ($mb MB): the Play button will work after deploy"
} else { Warn "site-assets/play/index.html is missing: the site's Play button will 404 (see docs/RELEASE.md)" }

# 5. .gitignore coverage.
$gi = if (Test-Path ".gitignore") { Get-Content ".gitignore" } else { @() }
foreach ($need in @('build/', '.godot/')) {
    if ($gi -contains $need -or $gi -contains $need.TrimEnd('/')) { Ok ".gitignore covers $need" } else { Err ".gitignore is missing $need" }
}
foreach ($need in @('*.keystore', '*.jks')) {
    if ($gi -contains $need) { Ok ".gitignore covers $need" } else { Warn ".gitignore does not list $need (add it as a safety net)" }
}

# 6. Licence and credits files.
foreach ($f in @('LICENSE', 'README.md', 'docs/ASSETS.md')) {
    if (Test-Path $f) { Ok "$f exists" } else { Err "$f is missing" }
}

# 7. LFS and remote hints.
if ((Test-Path ".gitattributes") -and (Select-String -Path ".gitattributes" -Pattern "filter=lfs" -Quiet)) {
    git lfs version *> $null
    if ($LASTEXITCODE -ne 0) { Warn ".gitattributes routes files through Git LFS but git-lfs is not installed: adds of .wav/.glb/.fbx/.ogg/.blend will fail or commit pointers" }
    else { Ok "git-lfs is installed" }
}
$remote = git remote 2>$null
if (-not $remote) { Warn "no git remote configured yet" } else { Ok "remote: $(git remote get-url origin 2>$null)" }

Write-Host ""
Write-Host "$($errors.Count) error(s), $($warns.Count) warning(s)."
if ($errors.Count -gt 0) { exit 1 } else { exit 0 }

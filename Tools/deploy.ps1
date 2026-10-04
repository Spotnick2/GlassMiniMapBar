<#
    deploy.ps1 - Copy GlassMiniMapBar into the Forever AddOns folder.

    Copies exactly the files the TOC lists (the vendored Libs included) plus
    Media\*.tga (the orb textures), and removes Lua files the TOC no longer
    lists. The repo keeps "## Version: @project-version@" for the packager; the
    deployed copy gets "dev". The repo copy is never modified.

    The glass material is the embedded LibGlass-1.0. The packager fetches it
    into Libs\LibGlass-1.0 (.pkgmeta externals); for a dev copy this script
    hands that job to the LibGlass checkout's own deploy.ps1, which checks the
    checkout, copies only the shipped files and prints its commit. The checkout
    is $env:LIBGLASS, else ..\LibGlass.

    Usage:
        pwsh Tools/deploy.ps1
        pwsh Tools/deploy.ps1 -AddOnsPath "D:\...\_classic_beta_\Interface\AddOns"
#>

param(
    [string]$AddOnsPath = "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path $AddOnsPath)) { Write-Error "AddOns path not found: $AddOnsPath"; exit 1 }

$LibGlass = if ($env:LIBGLASS) { $env:LIBGLASS } else { Join-Path (Split-Path -Parent $RepoRoot) "LibGlass" }
if (-not (Test-Path -LiteralPath (Join-Path $LibGlass "Tools\deploy.ps1"))) {
    Write-Error "LibGlass checkout not found at $LibGlass (clone github.com/Spotnick2/LibGlass there, or set `$env:LIBGLASS)"
    exit 1
}

# The tag .pkgmeta pins is what the packager will ship. A dev checkout
# elsewhere is legitimate (trying a library change before a pin bump), but an
# in-game check then tests something the release won't carry: say so.
$pin = (Get-Content -LiteralPath (Join-Path $RepoRoot ".pkgmeta")) |
    Where-Object { $_ -match '^\s+(commit|tag):\s*(\S+)\s*$' } | ForEach-Object { $Matches[2] } | Select-Object -First 1
if (-not $pin) { Write-Host "  (no LibGlass pin found in .pkgmeta)" -ForegroundColor Yellow } else {
    $want = $null; $head = $null; $dirty = $null
    try {
        $want = (git -C $LibGlass rev-parse --verify --quiet "$pin^{commit}" 2>$null)
        $head = (git -C $LibGlass rev-parse HEAD 2>$null)
        $dirty = (git -C $LibGlass status --porcelain 2>$null)
    } catch { }
    if (-not $want -or $want -ne $head -or $dirty) {
        Write-Host "  WARNING: the LibGlass checkout is not at the .pkgmeta pin ($pin)$(if ($dirty) { ', or has uncommitted changes' }):" -ForegroundColor Yellow
        Write-Host "  this deploy tests a library the release won't ship." -ForegroundColor Yellow
    }
}

$tocName = "GlassMiniMapBar.toc"
$dest = Join-Path $AddOnsPath "GlassMiniMapBar"
$isNew = -not (Test-Path $dest)

# The library first: its deploy checks the checkout and may refuse, and a
# refusal must leave the deployed addon as it was (a new TOC naming a library
# that never arrived builds no bar at all).
& pwsh -NoProfile -File (Join-Path $LibGlass "Tools\deploy.ps1") -Addon GlassMiniMapBar -AddOnsPath $AddOnsPath
if ($LASTEXITCODE -ne 0) { Write-Error "LibGlass deploy refused; GlassMiniMapBar was not touched"; exit 1 }

Write-Host "Deploying GlassMiniMapBar -> $dest" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $dest | Out-Null

$toc = Join-Path $RepoRoot $tocName
(Get-Content -LiteralPath $toc -Raw) -replace '## Version: @project-version@', '## Version: dev' |
    Set-Content -LiteralPath (Join-Path $dest $tocName) -NoNewline
# Our files and the vendored Libs; the LibGlass line is the library deploy's.
$listed = Get-Content -LiteralPath $toc | ForEach-Object { $_.Trim() } |
    Where-Object { $_ -notmatch "^#" -and $_ -match "[.](lua|xml)$" -and $_ -notmatch "^Libs\\LibGlass-1\.0\\" }
foreach ($f in $listed) {
    $target = Join-Path $dest $f
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Copy-Item -LiteralPath (Join-Path $RepoRoot $f) -Destination $target -Force
    Write-Host "  $f"
}
# A Lua file removed from the TOC must not linger where the client finds it.
# Libs\LibGlass-1.0 belongs to the library's deploy, which just wrote it.
$keep = $listed | ForEach-Object { (Join-Path $dest $_).ToLower() }
$libDir = (Join-Path $dest "Libs\LibGlass-1.0").ToLower()
Get-ChildItem -LiteralPath $dest -Recurse -File -Filter "*.lua" |
    Where-Object { -not $_.FullName.ToLower().StartsWith($libDir) -and $keep -notcontains $_.FullName.ToLower() } | ForEach-Object {
        Write-Host "  removing stale $($_.Name)" -ForegroundColor DarkYellow
        Remove-Item -LiteralPath $_.FullName -Force
    }

# Media\ holds only our own textures now; the panel ones moved to the library.
$media = Join-Path $dest "Media"
New-Item -ItemType Directory -Force -Path $media | Out-Null
$textures = Get-ChildItem -LiteralPath (Join-Path $RepoRoot "Media") -Filter "*.tga"
foreach ($t in $textures) { Copy-Item -LiteralPath $t.FullName -Destination (Join-Path $media $t.Name) -Force }
Write-Host "  Media\  ($($textures.Count) textures)"
$ours = $textures | ForEach-Object { $_.Name }
Get-ChildItem -LiteralPath $media -File | Where-Object { $ours -notcontains $_.Name } | ForEach-Object {
    Write-Host "  removing stale Media\$($_.Name) (now from LibGlass)" -ForegroundColor DarkYellow
    Remove-Item -LiteralPath $_.FullName -Force
}

Write-Host ""
if ($isNew) {
    Write-Host "Brand-new addon folder: restart the client (a /reload won't find it)." -ForegroundColor Yellow
} else {
    Write-Host "Changed or new files: /reload is enough." -ForegroundColor Yellow
}
Write-Host "In game:  /console scriptErrors 1   then   /gmb scan" -ForegroundColor Green

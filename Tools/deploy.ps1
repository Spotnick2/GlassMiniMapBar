<#
    deploy.ps1 - Copy GlassMiniMapBar into the Forever AddOns folder.

    Copies exactly the files the TOC lists (Libs included) plus Media\*.tga,
    and removes Lua files the TOC no longer lists. The repo keeps
    "## Version: @project-version@" for the packager; the deployed copy gets
    "dev". The repo copy is never modified.

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

$tocName = "GlassMiniMapBar.toc"
$dest = Join-Path $AddOnsPath "GlassMiniMapBar"
$isNew = -not (Test-Path $dest)
Write-Host "Deploying GlassMiniMapBar -> $dest" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $dest | Out-Null

$toc = Join-Path $RepoRoot $tocName
(Get-Content -LiteralPath $toc -Raw) -replace '## Version: @project-version@', '## Version: dev' |
    Set-Content -LiteralPath (Join-Path $dest $tocName) -NoNewline
$listed = Get-Content -LiteralPath $toc | ForEach-Object { $_.Trim() } |
    Where-Object { $_ -notmatch "^#" -and $_ -match "[.](lua|xml)$" }
foreach ($f in $listed) {
    $target = Join-Path $dest $f
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Copy-Item -LiteralPath (Join-Path $RepoRoot $f) -Destination $target -Force
    Write-Host "  $f"
}
# A Lua file removed from the TOC must not linger where the client finds it.
$keep = $listed | ForEach-Object { (Join-Path $dest $_).ToLower() }
Get-ChildItem -LiteralPath $dest -Recurse -File -Filter "*.lua" |
    Where-Object { $keep -notcontains $_.FullName.ToLower() } | ForEach-Object {
        Write-Host "  removing stale $($_.Name)" -ForegroundColor DarkYellow
        Remove-Item -LiteralPath $_.FullName -Force
    }

$media = Join-Path $dest "Media"
New-Item -ItemType Directory -Force -Path $media | Out-Null
$textures = Get-ChildItem -LiteralPath (Join-Path $RepoRoot "Media") -Filter "*.tga"
foreach ($t in $textures) { Copy-Item -LiteralPath $t.FullName -Destination (Join-Path $media $t.Name) -Force }
Write-Host "  Media\  ($($textures.Count) textures)"

Write-Host ""
if ($isNew) {
    Write-Host "Brand-new addon folder: restart the client (a /reload won't find it)." -ForegroundColor Yellow
} else {
    Write-Host "Changed files: /reload is enough." -ForegroundColor Yellow
}
Write-Host "In game:  /console scriptErrors 1   then   /gmb scan" -ForegroundColor Green

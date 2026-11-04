<#
    run.ps1 - Syntax-check the addon and run every tests\test_*.lua under Lua 5.1,
    through WowTestKit's runner at the commit tests\kit.pin names (its README).

    Usage:
        pwsh tests/run.ps1
        pwsh tests/run.ps1 -Lua "C:\path\to\lua5.1.exe"
        pwsh tests/run.ps1 -KitDev      # the ..\WowTestKit working copy, not the pin
#>

param(
    [string]$Lua = "C:\Program Files (x86)\Lua\5.1\lua.exe",
    [switch]$KitDev
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

# The tests load the LibGlass checkout as it is (the TOC's .xml line, not
# syntax-checked here: that's its repo's job); CI loads the .pkgmeta pin.
# Running against something else is fine (a library change before a pin
# bump) but must not pass for a check of what ships.
$libGlass = if ($env:LIBGLASS) { $env:LIBGLASS } else { Join-Path (Split-Path -Parent $RepoRoot) "LibGlass" }
$pin = (Get-Content (Join-Path $RepoRoot ".pkgmeta")) | Where-Object { $_ -match '^\s+(commit|tag):\s*(\S+)\s*$' } |
    ForEach-Object { $Matches[2] } | Select-Object -First 1
if ($pin -and (Test-Path -LiteralPath $libGlass)) {
    # A warning only: no git, or a checkout that isn't a repo, must not stop the tests.
    $want = $null; $head = $null; $dirty = $null
    try {
        $want = git -C $libGlass rev-parse --verify --quiet "$pin^{commit}" 2>$null
        $head = git -C $libGlass rev-parse HEAD 2>$null
        $dirty = git -C $libGlass status --porcelain 2>$null
    } catch { }
    if (-not $want -or $want -ne $head -or $dirty) {
        Write-Host "WARNING: LibGlass at $libGlass is not the .pkgmeta pin ($pin)$(if ($dirty) { ', or has uncommitted changes' }); CI tests the pin" -ForegroundColor Yellow
    } else {
        Write-Host "LibGlass: $libGlass at the pin ($pin)" -ForegroundColor DarkGray
    }
}

. (Join-Path $PSScriptRoot "kit.ps1")
$kit = Get-WowTestKit -RepoRoot $RepoRoot -KitDev:$KitDev
& (Join-Path $kit "scripts\run.ps1") -RepoRoot $RepoRoot -Toc "GlassMiniMapBar.toc" -Lua $Lua
exit $LASTEXITCODE

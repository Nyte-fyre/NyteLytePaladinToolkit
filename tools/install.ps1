# Links this repo into the WoW AddOns folder as "NyteLytePaladinToolkit" (a directory
# junction, so edits are live after /reload; no admin rights needed).
#   powershell -ExecutionPolicy Bypass -File tools\install.ps1
#   powershell -ExecutionPolicy Bypass -File tools\install.ps1 -Copy   # copy instead of link
# Set WOW_ADDONS_DIR to override the default (Forever beta) AddOns path.
param([switch]$Copy)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$addons = $env:WOW_ADDONS_DIR
if (-not $addons) {
    $addons = "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns"
}
if (-not (Test-Path $addons)) {
    throw "AddOns folder not found: $addons (set WOW_ADDONS_DIR)"
}
$target = Join-Path $addons "NyteLytePaladinToolkit"

if (Test-Path $target) {
    $item = Get-Item $target -Force
    if ($item.LinkType -eq "Junction" -or $item.LinkType -eq "SymbolicLink") {
        # Removing a junction removes only the link, never the repo files.
        $item.Delete()
    } else {
        throw "$target exists and is a real folder. Move or delete it yourself, then re-run."
    }
}

if ($Copy) {
    $exclude = @(".git", "tests", "tools", "docs")
    New-Item -ItemType Directory -Path $target | Out-Null
    Get-ChildItem $repo -Force | Where-Object { $exclude -notcontains $_.Name -and $_.Name -notlike ".*" } |
        Copy-Item -Destination $target -Recurse
    Write-Host "Copied NyteLytePaladinToolkit to $target"
} else {
    New-Item -ItemType Junction -Path $target -Target $repo | Out-Null
    Write-Host "Linked $target -> $repo"
}

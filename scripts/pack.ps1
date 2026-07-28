# pack.ps1 - builds the release zip from this repo.
#
# The zip and the repo hold the same files on purpose, so a reader can compare
# what they downloaded against what is published here. This script is only doing
# two things: putting everything under one top-level folder (so unzipping does
# not spray files into someone's Downloads), and leaving out the files that are
# for GitHub rather than for players.
#
#   powershell -ExecutionPolicy Bypass -File scripts/pack.ps1 -Version 1.0
#
# Output: dist/NAG Overlay Enhancements v<Version>.zip

param(
    [string] $Version = '1.0'
)

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$dist = Join-Path $repo 'dist'
$name = 'NAG Overlay Enhancements'
$zip  = Join-Path $dist "$name v$Version.zip"

# Repo-only files. Everything else ships.
$exclude = @('.git', '.gitattributes', '.gitignore', 'README.md', 'LICENSE', 'scripts', 'dist')

# Stage under a folder named for the product, so the zip has one clean root.
$stage = Join-Path ([System.IO.Path]::GetTempPath()) ("nag-pack-" + [System.Guid]::NewGuid().ToString('N'))
$root  = Join-Path $stage $name
New-Item -ItemType Directory -Path $root -Force | Out-Null

try {
    Get-ChildItem -Path $repo -Force |
        Where-Object { $exclude -notcontains $_.Name } |
        ForEach-Object { Copy-Item $_.FullName -Destination $root -Recurse -Force }

    if (Test-Path $zip) { Remove-Item $zip -Force }
    New-Item -ItemType Directory -Path $dist -Force | Out-Null

    Compress-Archive -Path $root -DestinationPath $zip -CompressionLevel Optimal

    $size = [math]::Round((Get-Item $zip).Length / 1KB)
    Write-Host ""
    Write-Host "Built $zip ($size KB)" -ForegroundColor Green
    Write-Host "Copy it to the site's public/downloads/ to publish it." -ForegroundColor DarkGray
}
finally {
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
}

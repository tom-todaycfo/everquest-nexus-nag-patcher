# revert-nag.ps1 - restores EQ NAG's original app.asar (removes the patch).
$ErrorActionPreference = 'Stop'

function Find-NagDir {
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\electron-angular-eq-parse",
        "$env:LOCALAPPDATA\electron-angular-eq-parse",
        "$env:ProgramFiles\electron-angular-eq-parse",
        (Join-Path ${env:ProgramFiles(x86)} 'electron-angular-eq-parse')
    )
    foreach ($c in $candidates) { if ($c -and (Test-Path (Join-Path $c 'resources\app.asar'))) { return $c } }
    foreach ($root in @("$env:LOCALAPPDATA\Programs", "$env:LOCALAPPDATA")) {
        if (Test-Path $root) {
            $hit = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
                   Where-Object { Test-Path (Join-Path $_.FullName 'resources\app.asar') } |
                   Where-Object { $_.Name -match 'eq|nag|parse' } | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }
    return $null
}

Write-Host ""
Write-Host "=== EQ NAG : revert to original ===" -ForegroundColor Cyan
$dir = Find-NagDir
if (-not $dir) { Write-Host "Could not find NAG install." -ForegroundColor Red; exit 1 }
$res = Join-Path $dir 'resources'
$orig = Join-Path $res 'app.asar.orig'
if (-not (Test-Path $orig)) {
    Write-Host "No backup (app.asar.orig) found - nothing to revert to." -ForegroundColor Yellow
    exit 1
}

$running = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($dir, 'OrdinalIgnoreCase') }
if ($running) { Write-Host "Closing NAG ..."; $running | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 1200 }

Copy-Item $orig (Join-Path $res 'app.asar') -Force
Write-Host "Restored original app.asar. The patch has been removed." -ForegroundColor Green
$exe = Get-ChildItem $dir -Filter '*.exe' -ErrorAction SilentlyContinue |
       Where-Object { $_.Name -notmatch 'elevate|Uninstall|crashpad|Squirrel' } | Select-Object -First 1
if ($exe) { $ans = Read-Host "Launch NAG now? (Y/n)"; if ($ans -notmatch '^[Nn]') { Start-Process $exe.FullName } }

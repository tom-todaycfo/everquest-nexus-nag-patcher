# patch-nag.ps1 - installs the "focus-follows-EQ" auto-hide feature into EQ NAG.
# No prerequisites: it uses NAG's own bundled runtime to do the work.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Find-NagDir {
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\electron-angular-eq-parse",
        "$env:LOCALAPPDATA\electron-angular-eq-parse",
        "$env:ProgramFiles\electron-angular-eq-parse",
        (Join-Path ${env:ProgramFiles(x86)} 'electron-angular-eq-parse')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path (Join-Path $c 'resources\app.asar'))) { return $c }
    }
    # Fallback: shallow recursive search under common roots.
    foreach ($root in @("$env:LOCALAPPDATA\Programs", "$env:LOCALAPPDATA")) {
        if (Test-Path $root) {
            $hit = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
                   Where-Object { Test-Path (Join-Path $_.FullName 'resources\app.asar') } |
                   Where-Object { $_.Name -match 'eq|nag|parse' } |
                   Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }
    return $null
}

Write-Host ""
Write-Host "=== EQ NAG : Focus-Follows-EQ patch ===" -ForegroundColor Cyan
Write-Host ""

$dir = Find-NagDir
if (-not $dir) {
    Write-Host "Could not find your EQ NAG installation automatically." -ForegroundColor Red
    Write-Host "Expected a folder containing 'resources\app.asar' (usually" -ForegroundColor Red
    Write-Host "  %LOCALAPPDATA%\Programs\electron-angular-eq-parse )." -ForegroundColor Red
    Write-Host "If NAG is installed somewhere unusual, edit this script's candidate list." -ForegroundColor Red
    exit 1
}
$res = Join-Path $dir 'resources'
$exe = Get-ChildItem $dir -Filter '*.exe' -ErrorAction SilentlyContinue |
       Where-Object { $_.Name -notmatch 'elevate|Uninstall|crashpad|Squirrel' } |
       Select-Object -First 1
if (-not $exe) { Write-Host "Found NAG at $dir but no launcher .exe. Aborting." -ForegroundColor Red; exit 1 }

Write-Host "Found NAG:  $dir"
Write-Host "Runtime:    $($exe.Name)"
Write-Host ""

# Close NAG so its files unlock.
$running = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($dir, 'OrdinalIgnoreCase') }
if ($running) {
    Write-Host "Closing NAG ($($running.Count) process(es)) ..."
    $running | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 1200
}

# Run the patcher using NAG's own Electron binary as Node (no Node install needed).
# Electron is a GUI-subsystem exe, so we start it with -PassThru (no -Wait) and
# stream its progress live from the redirected output file, showing a spinner so
# the long unpack/repack steps never look frozen. Paths are explicitly quoted.
$argline = '"{0}" "{1}" "{2}"' -f (Join-Path $here 'apply.js'), $res, (Join-Path $here 'lib')
$outFile = Join-Path $env:TEMP 'nag-patch-out.txt'
$errFile = Join-Path $env:TEMP 'nag-patch-err.txt'
Set-Content -Path $outFile -Value '' -NoNewline -ErrorAction SilentlyContinue
Set-Content -Path $errFile -Value '' -NoNewline -ErrorAction SilentlyContinue

# Reads bytes appended to $File since offset $Pos; tolerant of the writer holding it
# open. Reads an EXACT byte count and advances $Pos by bytes actually read, so a file
# that grows mid-read is never double-counted (which would duplicate output).
function Read-Appended {
    param([string]$File, [ref]$Pos)
    try {
        if (-not (Test-Path $File)) { return '' }
        $len = (Get-Item $File).Length
        if ($len -le $Pos.Value) { return '' }
        $count = [int]($len - $Pos.Value)
        $fs = [System.IO.File]::Open($File, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        [void]$fs.Seek($Pos.Value, [System.IO.SeekOrigin]::Begin)
        $buf = New-Object byte[] $count
        $read = $fs.Read($buf, 0, $count)
        $fs.Close()
        $Pos.Value = $Pos.Value + $read
        return [System.Text.Encoding]::UTF8.GetString($buf, 0, $read)
    } catch { return '' }
}

Write-Host "Working (this takes up to a minute - please wait) ..." -ForegroundColor DarkGray
$env:ELECTRON_RUN_AS_NODE = '1'
$proc = Start-Process -FilePath $exe.FullName -ArgumentList $argline -NoNewWindow -PassThru `
                      -RedirectStandardOutput $outFile -RedirectStandardError $errFile
Remove-Item Env:\ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue

$spin = '|','/','-','\'
$si = 0
$pos = 0
$spinnerShown = $false
$allOut = ''
while (-not $proc.HasExited) {
    $new = Read-Appended $outFile ([ref]$pos)
    if ($new) {
        $allOut += $new
        if ($spinnerShown) { Write-Host ("`r" + (' ' * 24) + "`r") -NoNewline; $spinnerShown = $false }
        Write-Host -NoNewline $new
    } else {
        Write-Host ("`r  working {0}   " -f $spin[$si % 4]) -NoNewline
        $spinnerShown = $true; $si++
    }
    Start-Sleep -Milliseconds 200
}
if ($spinnerShown) { Write-Host ("`r" + (' ' * 24) + "`r") -NoNewline }
$tail = Read-Appended $outFile ([ref]$pos)
if ($tail) { $allOut += $tail; Write-Host -NoNewline $tail }

# Determine success from the patcher's own output (Start-Process -PassThru without
# -Wait doesn't reliably populate ExitCode), backed up by stderr.
$errText = Get-Content $errFile -ErrorAction SilentlyContinue
$ok = ($allOut -match 'DONE - patched' -or $allOut -match 'Already fully patched')
if ($errText) { Write-Host ""; Write-Host ($errText -join "`n") -ForegroundColor Yellow }
Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue

Write-Host ""
if ($ok) {
    Write-Host "Success! Overlay auto-hide + multi-monitor/sleep recovery are installed." -ForegroundColor Green
    Write-Host "Launch NAG, right-click its tray icon, and tick" -ForegroundColor Green
    Write-Host "  'Auto-hide overlay when tabbed out of EQ'." -ForegroundColor Green
    Write-Host ""
    $ans = Read-Host "Launch NAG now? (Y/n)"
    if ($ans -notmatch '^[Nn]') { Start-Process -FilePath $exe.FullName }
} else {
    Write-Host "Patch did NOT complete (see the message above). Your NAG is unchanged;" -ForegroundColor Yellow
    Write-Host "a backup is at $res\app.asar.orig if you need it." -ForegroundColor Yellow
    exit 1
}

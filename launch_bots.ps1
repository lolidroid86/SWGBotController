#Requires -Version 5.1
# SWG Bot Launcher - Phase 1
# Launches multiple SWGEmu clients with per-bot auto-login and grid layout.
# Uses per-bot patched EXEs with unique mutex names to allow multiple instances.

param(
    [string]$ConfigFile = "$PSScriptRoot\bots.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Load config ---
$config      = Get-Content $ConfigFile -Raw | ConvertFrom-Json
$swgDir      = $config.swgDir
$swgExe      = Join-Path $swgDir "SWGEmu.exe"
$userCfgPath = Join-Path $swgDir "user.cfg"
$swgCfgPath  = Join-Path $swgDir "swgemu.cfg"
$delaySec    = $config.startupDelaySec
$cols        = $config.layout.columns
$winW        = $config.layout.windowWidth
$winH        = $config.layout.windowHeight

if (-not (Test-Path $swgExe)) {
    Write-Error "SWGEmu.exe not found at: $swgExe"
    exit 1
}

# --- Ensure swgemu.cfg includes user.cfg ---
$swgCfg = Get-Content $swgCfgPath -Raw
if ($swgCfg -match '#\.include "user\.cfg"') {
    $swgCfg = $swgCfg -replace '#\.include "user\.cfg"', '.include "user.cfg"'
    [System.IO.File]::WriteAllText($swgCfgPath, $swgCfg, [System.Text.Encoding]::ASCII)
    Write-Host "[setup] Enabled user.cfg include in swgemu.cfg"
}

# --- Patch exe: replace mutex name so each bot instance can run independently ---
# Original: "SwgClientInstanceRunning" (24 bytes)
# Per-bot:  "SwgClientInstanceBot0001" (24 bytes)
function Get-BotExe {
    param([int]$Index)
    $id   = "{0:D4}" -f ($Index + 1)
    $dest = Join-Path $swgDir "SWGEmu_bot$id.exe"
    if (-not (Test-Path $dest)) {
        Write-Host "  [patch] Creating $dest"
        $oldBytes = [System.Text.Encoding]::ASCII.GetBytes("SwgClientInstanceRunning")
        $newBytes = [System.Text.Encoding]::ASCII.GetBytes("SwgClientInstanceBot$id")
        $exeBytes = [System.IO.File]::ReadAllBytes($swgExe)
        $patched  = 0
        for ($i = 0; $i -le $exeBytes.Length - $oldBytes.Length; $i++) {
            $match = $true
            for ($j = 0; $j -lt $oldBytes.Length; $j++) {
                if ($exeBytes[$i + $j] -ne $oldBytes[$j]) { $match = $false; break }
            }
            if ($match) {
                for ($j = 0; $j -lt $newBytes.Length; $j++) {
                    $exeBytes[$i + $j] = $newBytes[$j]
                }
                $patched++
            }
        }
        [System.IO.File]::WriteAllBytes($dest, $exeBytes)
        Write-Host "  [patch] Done ($patched occurrence(s) replaced)"
    }
    return $dest
}

# --- Win32 API ---
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndAfter,
        int X, int Y, int cx, int cy, uint flags);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public const uint SWP_NOZORDER   = 0x0004;
    public const uint SWP_NOACTIVATE = 0x0010;
    public const int  SW_MINIMIZE    = 6;
}
"@

function Wait-WindowHandle {
    param([System.Diagnostics.Process]$Proc, [int]$TimeoutSec = 30)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $Proc.Refresh()
        $h = $Proc.MainWindowHandle
        if ($h -ne $null -and $h.ToInt64() -ne 0) { return $h }
        Start-Sleep -Milliseconds 500
    }
    return $null
}

# --- Launch loop ---
$procs = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()

for ($i = 0; $i -lt $config.bots.Count; $i++) {
    $bot    = $config.bots[$i]
    $botExe = Get-BotExe -Index $i
    Write-Host "[launch] $($bot.username) via $(Split-Path $botExe -Leaf)"

    $userCfg = "[ClientGame]`r`nloginClientID=$($bot.username)`r`nloginClientPassword=$($bot.password)`r`nautoConnectToLoginServer=1`r`n`r`n[ClientGraphics]`r`nscreenWidth=$winW`r`nscreenHeight=$winH`r`nwindowed=1`r`n"
    [System.IO.File]::WriteAllText($userCfgPath, $userCfg, [System.Text.Encoding]::ASCII)

    $proc = Start-Process -FilePath $botExe -WorkingDirectory $swgDir -PassThru
    $procs.Add($proc)

    Write-Host "  PID $($proc.Id) - waiting ${delaySec}s for config read..."
    Start-Sleep -Seconds $delaySec
}

Write-Host ""
Write-Host "[layout] Arranging $($procs.Count) windows in $cols-column grid (${winW}x${winH})..."

for ($i = 0; $i -lt $procs.Count; $i++) {
    $proc = $procs[$i]
    $col  = $i % $cols
    $row  = [Math]::Floor($i / $cols)
    $x    = $col * $winW
    $y    = $row * $winH

    Write-Host "  $($config.bots[$i].username) -> grid ($col,$row) pixel ($x,$y)"
    $hwnd = Wait-WindowHandle -Proc $proc -TimeoutSec 20
    if ($hwnd -ne $null) {
        [Win32]::SetWindowPos($hwnd, [IntPtr]::Zero, $x, $y, $winW, $winH,
            [Win32]::SWP_NOZORDER -bor [Win32]::SWP_NOACTIVATE) | Out-Null
        [Win32]::ShowWindow($hwnd, [Win32]::SW_MINIMIZE) | Out-Null
        Write-Host "  Minimized"
    } else {
        Write-Warning "  Could not find window for PID $($proc.Id)"
    }
}

# --- Clean up user.cfg so normal play is not affected ---
Write-Host ""
Write-Host "[cleanup] Removing user.cfg"
Remove-Item $userCfgPath -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "[done] All bots launched. Close this window to exit."

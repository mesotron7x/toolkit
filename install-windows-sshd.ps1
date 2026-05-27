<#
.SYNOPSIS
Installs and enables Windows OpenSSH Server.

.DESCRIPTION
This script installs the built-in Windows OpenSSH Server optional feature,
starts the sshd service, enables it at startup, and ensures TCP/22 is allowed
through Windows Defender Firewall.

One-line install:
  irm https://raw.githubusercontent.com/mesotron7x/toolkit/main/install-windows-sshd.ps1 | iex

The script is idempotent and can be re-run safely.
#>

[CmdletBinding()]
param(
    [switch]$SkipFirewall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$InstallerUrl = "https://raw.githubusercontent.com/mesotron7x/toolkit/main/install-windows-sshd.ps1"
$CapabilityName = "OpenSSH.Server~~~~0.0.1.0"
$FirewallRuleName = "OpenSSH-Server-In-TCP"

function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "    $Message" -ForegroundColor Green
}

function Test-IsWindows {
    return [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-Elevated {
    Write-Step "Administrator privileges are required"
    Write-Host "A UAC prompt will appear. The installer will continue in an elevated PowerShell window."

    $command = "Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force; irm '$InstallerUrl' | iex"
    if ($SkipFirewall) {
        $command = "Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force; & ([scriptblock]::Create((irm '$InstallerUrl'))) -SkipFirewall"
    }

    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-Command", $command
    ) | Out-Null

    exit 0
}

function Install-OpenSSHServer {
    Write-Step "Checking Windows OpenSSH Server optional feature"

    $capability = Get-WindowsCapability -Online -Name $CapabilityName

    if ($capability.State -eq "Installed") {
        Write-Ok "OpenSSH Server is already installed."
        return
    }

    Write-Step "Installing OpenSSH Server"
    Add-WindowsCapability -Online -Name $CapabilityName | Out-Null

    $capability = Get-WindowsCapability -Online -Name $CapabilityName
    if ($capability.State -ne "Installed") {
        throw "OpenSSH Server installation did not complete. Current state: $($capability.State)"
    }

    Write-Ok "OpenSSH Server installed."
}

function Enable-SSHDService {
    Write-Step "Enabling sshd service"

    $service = Get-Service -Name sshd -ErrorAction Stop

    if ($service.StartType -ne "Automatic") {
        Set-Service -Name sshd -StartupType Automatic
    }

    if ($service.Status -ne "Running") {
        Start-Service -Name sshd
    }

    $service = Get-Service -Name sshd
    Write-Ok "sshd status: $($service.Status); startup type: $($service.StartType)."
}

function Enable-SSHDFirewallRule {
    if ($SkipFirewall) {
        Write-Step "Skipping firewall configuration"
        return
    }

    Write-Step "Ensuring Windows Defender Firewall allows TCP/22"

    $rule = Get-NetFirewallRule -Name $FirewallRuleName -ErrorAction SilentlyContinue

    if ($null -ne $rule) {
        Enable-NetFirewallRule -Name $FirewallRuleName | Out-Null
        Write-Ok "Enabled existing firewall rule: $FirewallRuleName."
        return
    }

    New-NetFirewallRule `
        -Name $FirewallRuleName `
        -DisplayName "OpenSSH Server (sshd)" `
        -Enabled True `
        -Direction Inbound `
        -Protocol TCP `
        -Action Allow `
        -LocalPort 22 `
        -Profile Any | Out-Null

    Write-Ok "Created firewall rule for TCP/22."
}

function Show-Summary {
    Write-Step "Verifying installation"

    $service = Get-Service -Name sshd -ErrorAction Stop
    $listener = Get-NetTCPConnection -LocalPort 22 -State Listen -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "Windows OpenSSH Server setup complete." -ForegroundColor Green
    Write-Host ""
    Write-Host "Service"
    Write-Host "  Name       : $($service.Name)"
    Write-Host "  Status     : $($service.Status)"
    Write-Host "  Start type : $($service.StartType)"
    Write-Host ""

    if ($listener) {
        Write-Host "Port"
        Write-Host "  TCP/22     : listening"
    }
    else {
        Write-Warning "TCP/22 is not currently reported as listening. Try: Restart-Service sshd"
    }

    Write-Host ""
    Write-Host "Local test:"
    Write-Host "  ssh localhost"
    Write-Host ""
    Write-Host "Find this machine's LAN IP:"
    Write-Host "  ipconfig"
    Write-Host ""
    Write-Host "Connect from another machine:"
    Write-Host "  ssh <windows-username>@<windows-ip>"
}

try {
    if (-not (Test-IsWindows)) {
        throw "This installer only supports Windows."
    }

    if (-not (Test-IsAdministrator)) {
        Restart-Elevated
    }

    Install-OpenSSHServer
    Enable-SSHDService
    Enable-SSHDFirewallRule
    Show-Summary
}
catch {
    Write-Host ""
    Write-Host "Installation failed:" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Common causes:"
    Write-Host "  - Windows Update or Feature on Demand access is blocked."
    Write-Host "  - Enterprise WSUS policy prevents optional feature installation."
    Write-Host "  - PowerShell was interrupted during installation."
    exit 1
}

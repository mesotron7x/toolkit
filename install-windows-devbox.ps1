<#
.SYNOPSIS
Bootstraps a Windows development host for SSH access and basic CLI tools.

.DESCRIPTION
This script installs and configures the following components:

- Windows OpenSSH Server
- Google Chrome through winget
- Scoop
- Git, Vim, and PowerShell 7 through Scoop
- OpenSSH default shell set to PowerShell 7
- C:\ProgramData\ssh\administrators_authorized_keys with hardened ACLs

One-line install:
  irm https://raw.githubusercontent.com/mesotron7x/toolkit/main/install-windows-devbox.ps1 | iex

The script is idempotent and can be re-run safely.
#>

[CmdletBinding()]
param(
    [switch]$SkipFirewall,
    [switch]$SkipChrome,
    [switch]$SkipScoopTools,
    [switch]$SkipAdminAuthorizedKeys
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$InstallerUrl = "https://raw.githubusercontent.com/mesotron7x/toolkit/main/install-windows-devbox.ps1"
$OpenSSHCapabilityName = "OpenSSH.Server~~~~0.0.1.0"
$FirewallRuleName = "OpenSSH-Server-In-TCP"
$OpenSSHRegistryPath = "HKLM:\SOFTWARE\OpenSSH"
$AdminAuthorizedKeysPath = Join-Path $env:ProgramData "ssh\administrators_authorized_keys"
$ChromeWingetId = "Google.Chrome"
$ScoopPackageNames = @("git", "vim", "pwsh")

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

    $forwardedArgs = @()
    if ($SkipFirewall) { $forwardedArgs += "-SkipFirewall" }
    if ($SkipChrome) { $forwardedArgs += "-SkipChrome" }
    if ($SkipScoopTools) { $forwardedArgs += "-SkipScoopTools" }
    if ($SkipAdminAuthorizedKeys) { $forwardedArgs += "-SkipAdminAuthorizedKeys" }

    $argText = $forwardedArgs -join " "
    $command = "Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force; & ([scriptblock]::Create((irm '$InstallerUrl'))) $argText"

    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-Command", $command
    ) | Out-Null

    exit 0
}

function Add-PathEntryForCurrentProcess {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $currentEntries = $env:Path -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($currentEntries -notcontains $Path) {
        $env:Path = "$Path;$env:Path"
    }
}

function Update-CurrentProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = @($machinePath, $userPath, $env:Path) -join ";"

    $scoopRoot = Get-ScoopRoot
    Add-PathEntryForCurrentProcess -Path (Join-Path $scoopRoot "shims")
}

function Get-ScoopRoot {
    if (-not [string]::IsNullOrWhiteSpace($env:SCOOP)) {
        return $env:SCOOP
    }

    return Join-Path $env:USERPROFILE "scoop"
}

function Get-RegistryStringValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )

    try {
        $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return $item.$Name
    }
    catch {
        return $null
    }
}

function Install-OpenSSHServer {
    Write-Step "Checking Windows OpenSSH Server optional feature"

    $capability = Get-WindowsCapability -Online -Name $OpenSSHCapabilityName

    if ($capability.State -eq "Installed") {
        Write-Ok "OpenSSH Server is already installed."
        return
    }

    Write-Step "Installing OpenSSH Server"
    Add-WindowsCapability -Online -Name $OpenSSHCapabilityName | Out-Null

    $capability = Get-WindowsCapability -Online -Name $OpenSSHCapabilityName
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

function Test-ChromeInstalled {
    $chromePaths = @(
        (Join-Path $env:ProgramFiles "Google\Chrome\Application\chrome.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Google\Chrome\Application\chrome.exe"),
        (Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe")
    )

    foreach ($chromePath in $chromePaths) {
        if (-not [string]::IsNullOrWhiteSpace($chromePath) -and (Test-Path -LiteralPath $chromePath)) {
            return $true
        }
    }

    $uninstallRegistryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($registryPath in $uninstallRegistryPaths) {
        $matches = Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -eq "Google Chrome" }

        if ($matches) {
            return $true
        }
    }

    return $false
}

function Install-ChromeWithWinget {
    if ($SkipChrome) {
        Write-Step "Skipping Google Chrome installation"
        return
    }

    Write-Step "Checking Google Chrome"

    if (Test-ChromeInstalled) {
        Write-Ok "Google Chrome is already installed."
        return
    }

    Update-CurrentProcessPath

    $wingetCommand = Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $wingetCommand) {
        throw "winget.exe was not found. Install or update App Installer from Microsoft Store, then re-run this script."
    }

    Write-Step "Installing Google Chrome through winget"
    & $wingetCommand.Source install `
        --id $ChromeWingetId `
        --exact `
        --source winget `
        --silent `
        --accept-package-agreements `
        --accept-source-agreements

    if ($LASTEXITCODE -ne 0) {
        throw "winget install --id $ChromeWingetId failed with exit code $LASTEXITCODE."
    }

    if (-not (Test-ChromeInstalled)) {
        throw "winget completed, but Google Chrome was not detected after installation."
    }

    Write-Ok "Google Chrome installed."
}

function Test-ScoopInstalled {
    Update-CurrentProcessPath
    return $null -ne (Get-Command scoop -ErrorAction SilentlyContinue)
}

function Install-Scoop {
    Write-Step "Checking Scoop"

    if (Test-ScoopInstalled) {
        Write-Ok "Scoop is already installed."
        return
    }

    Write-Step "Installing Scoop"
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force

    $installerContent = Invoke-RestMethod -Uri "https://get.scoop.sh"
    $installer = [scriptblock]::Create($installerContent)
    & $installer -RunAsAdmin

    Update-CurrentProcessPath

    if (-not (Test-ScoopInstalled)) {
        throw "Scoop installation completed, but the scoop command is not available in PATH."
    }

    Write-Ok "Scoop installed."
}

function Invoke-Scoop {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    Update-CurrentProcessPath
    & scoop @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "scoop $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

function Test-ScoopPackageInstalled {
    param([Parameter(Mandatory = $true)][string]$Name)

    $packageCurrentPath = Join-Path (Get-ScoopRoot) "apps\$Name\current"
    return Test-Path -LiteralPath $packageCurrentPath
}

function Install-ScoopPackage {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (Test-ScoopPackageInstalled -Name $Name) {
        Write-Ok "Scoop package '$Name' is already installed."
        return
    }

    Write-Step "Installing Scoop package: $Name"
    Invoke-Scoop -Arguments @("install", $Name)
    Write-Ok "Installed Scoop package '$Name'."
}

function Install-DevelopmentTools {
    if ($SkipScoopTools) {
        Write-Step "Skipping Scoop tool installation"
        return
    }

    Install-Scoop

    foreach ($packageName in $ScoopPackageNames) {
        Install-ScoopPackage -Name $packageName
    }
}

function Get-PwshPath {
    Update-CurrentProcessPath

    $scoopRoot = Get-ScoopRoot
    $candidates = @(
        (Join-Path $env:ProgramFiles "PowerShell\7\pwsh.exe"),
        (Join-Path $scoopRoot "apps\pwsh\current\pwsh.exe"),
        (Join-Path $scoopRoot "shims\pwsh.exe")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    $command = Get-Command pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $command) {
        return $command.Source
    }

    throw "PowerShell 7 executable pwsh.exe was not found."
}

function Set-OpenSSHDefaultShellToPwsh {
    Write-Step "Setting OpenSSH default shell to PowerShell 7"

    $pwshPath = Get-PwshPath

    New-Item -Path $OpenSSHRegistryPath -Force | Out-Null

    $currentShell = Get-RegistryStringValue -Path $OpenSSHRegistryPath -Name "DefaultShell"
    if ($currentShell -ne $pwshPath) {
        New-ItemProperty -Path $OpenSSHRegistryPath -Name "DefaultShell" -Value $pwshPath -PropertyType String -Force | Out-Null
        Write-Ok "DefaultShell set to $pwshPath."
    }
    else {
        Write-Ok "DefaultShell is already set to $pwshPath."
    }

    $currentShellCommandOption = Get-RegistryStringValue -Path $OpenSSHRegistryPath -Name "DefaultShellCommandOption"
    if ($currentShellCommandOption -ne "-c") {
        New-ItemProperty -Path $OpenSSHRegistryPath -Name "DefaultShellCommandOption" -Value "-c" -PropertyType String -Force | Out-Null
        Write-Ok "DefaultShellCommandOption set to -c."
    }
    else {
        Write-Ok "DefaultShellCommandOption is already set to -c."
    }

    Restart-Service -Name sshd -ErrorAction Stop
    Write-Ok "Restarted sshd to apply the default shell setting."
}

function Set-AdminAuthorizedKeysAcl {
    param([Parameter(Mandatory = $true)][string]$Path)

    $systemSid = [System.Security.Principal.SecurityIdentifier]::new("S-1-5-18")
    $administratorsSid = [System.Security.Principal.SecurityIdentifier]::new("S-1-5-32-544")

    $rights = [System.Security.AccessControl.FileSystemRights]::FullControl
    $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::None
    $propagationFlags = [System.Security.AccessControl.PropagationFlags]::None
    $accessType = [System.Security.AccessControl.AccessControlType]::Allow

    $acl = [System.Security.AccessControl.FileSecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)
    $acl.SetOwner($administratorsSid)

    foreach ($sid in @($systemSid, $administratorsSid)) {
        $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
            $sid,
            $rights,
            $inheritanceFlags,
            $propagationFlags,
            $accessType
        )
        $acl.AddAccessRule($rule)
    }

    Set-Acl -LiteralPath $Path -AclObject $acl
}

function Ensure-AdminAuthorizedKeysFile {
    if ($SkipAdminAuthorizedKeys) {
        Write-Step "Skipping administrators_authorized_keys creation"
        return
    }

    Write-Step "Ensuring administrators_authorized_keys exists with strict permissions"

    $sshDirectory = Split-Path -Parent $AdminAuthorizedKeysPath

    if (-not (Test-Path -LiteralPath $sshDirectory)) {
        New-Item -ItemType Directory -Path $sshDirectory -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $AdminAuthorizedKeysPath)) {
        New-Item -ItemType File -Path $AdminAuthorizedKeysPath -Force | Out-Null
        Write-Ok "Created $AdminAuthorizedKeysPath."
    }
    else {
        Write-Ok "$AdminAuthorizedKeysPath already exists."
    }

    Set-AdminAuthorizedKeysAcl -Path $AdminAuthorizedKeysPath
    Write-Ok "Applied strict ACLs to $AdminAuthorizedKeysPath."
}

function Show-Summary {
    Write-Step "Verifying bootstrap result"

    Update-CurrentProcessPath

    $service = Get-Service -Name sshd -ErrorAction Stop
    $listener = Get-NetTCPConnection -LocalPort 22 -State Listen -ErrorAction SilentlyContinue
    $pwshPath = Get-PwshPath
    $defaultShell = Get-RegistryStringValue -Path $OpenSSHRegistryPath -Name "DefaultShell"

    Write-Host ""
    Write-Host "Windows devbox bootstrap complete." -ForegroundColor Green
    Write-Host ""
    Write-Host "OpenSSH"
    Write-Host "  Service status       : $($service.Status)"
    Write-Host "  Service startup type : $($service.StartType)"
    Write-Host "  TCP/22 listening     : $([bool]$listener)"
    Write-Host "  Default shell        : $defaultShell"
    Write-Host "  Admin keys file      : $AdminAuthorizedKeysPath"
    Write-Host ""
    Write-Host "Tools"
    Write-Host "  Google Chrome        : $([bool](Test-ChromeInstalled))"
    Write-Host "  Scoop                : $([bool](Get-Command scoop -ErrorAction SilentlyContinue))"
    Write-Host "  Git                  : $([bool](Get-Command git.exe -ErrorAction SilentlyContinue))"
    Write-Host "  Vim                  : $([bool](Get-Command vim.exe -ErrorAction SilentlyContinue))"
    Write-Host "  PowerShell 7         : $pwshPath"
    Write-Host ""
    Write-Host "Local SSH test:"
    Write-Host "  ssh localhost"
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
    Install-ChromeWithWinget
    Install-DevelopmentTools
    Set-OpenSSHDefaultShellToPwsh
    Ensure-AdminAuthorizedKeysFile
    Show-Summary
}
catch {
    Write-Host ""
    Write-Host "Bootstrap failed:" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Common causes:"
    Write-Host "  - Windows Update or Feature on Demand access is blocked."
    Write-Host "  - winget or Scoop cannot reach GitHub, Microsoft Store, or package sources."
    Write-Host "  - A corporate proxy, antivirus, or execution policy blocks remote scripts."
    Write-Host "  - PowerShell was interrupted during installation."
    exit 1
}

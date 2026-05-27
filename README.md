# toolkit

A small collection of practical development utilities and setup scripts.

This repository is intended to host lightweight tools that make developer workstation setup, local infrastructure maintenance, and routine engineering tasks faster and more repeatable.

The scope is intentionally narrow:

- simple scripts that solve common setup or maintenance problems;
- tools that are easy to inspect before running;
- commands that can be used directly from a terminal;
- minimal dependencies unless a tool has a clear reason to require them.

## Available tools

### `install-windows-devbox.ps1`

Bootstraps a Windows development host for SSH access and basic CLI tooling.

It performs the following actions:

- installs the Windows `OpenSSH.Server~~~~0.0.1.0` optional feature;
- starts the `sshd` service and sets it to start automatically;
- enables or creates the Windows Defender Firewall rule for TCP/22;
- installs Scoop;
- installs Git, Vim, and PowerShell 7 through Scoop;
- sets the OpenSSH default shell to PowerShell 7;
- creates `C:\ProgramData\ssh\administrators_authorized_keys` and applies strict permissions;
- relaunches itself with UAC elevation when needed.

Run from PowerShell:

```powershell
irm https://raw.githubusercontent.com/mesotron7x/toolkit/main/install-windows-devbox.ps1 | iex
```

Optional flags:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/mesotron7x/toolkit/main/install-windows-devbox.ps1))) -SkipFirewall
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/mesotron7x/toolkit/main/install-windows-devbox.ps1))) -SkipScoopTools
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/mesotron7x/toolkit/main/install-windows-devbox.ps1))) -SkipAdminAuthorizedKeys
```

### `install-windows-sshd.ps1`

Installs and enables the built-in Windows OpenSSH Server.

It performs the following actions:

- installs the Windows `OpenSSH.Server~~~~0.0.1.0` optional feature;
- starts the `sshd` service;
- sets `sshd` to start automatically;
- enables or creates the Windows Defender Firewall rule for TCP/22;
- relaunches itself with UAC elevation when needed.

Run from PowerShell:

```powershell
irm https://raw.githubusercontent.com/mesotron7x/toolkit/main/install-windows-sshd.ps1 | iex
```

To skip firewall configuration:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/mesotron7x/toolkit/main/install-windows-sshd.ps1))) -SkipFirewall
```

## Safety note

The `irm ... | iex` pattern is convenient, but it executes remote code immediately. For a more auditable flow, download the script first, inspect it, and then run it:

```powershell
irm https://raw.githubusercontent.com/mesotron7x/toolkit/main/install-windows-devbox.ps1 -OutFile install-windows-devbox.ps1
notepad .\install-windows-devbox.ps1
powershell -ExecutionPolicy Bypass -File .\install-windows-devbox.ps1
```

## Language policy

Repository content should be written in English by default. Chinese should only be used when it is strictly necessary for a specific user environment, command output, or localized documentation context.

## License

No license has been declared yet.

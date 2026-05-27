# toolkit

A small collection of practical development utilities and setup scripts.

This repository currently focuses on one Windows bootstrap tool: `install-windows-devbox.ps1`.

It is intended to make a fresh Windows development host easier to access and use from a terminal by installing OpenSSH Server, Google Chrome, Scoop, Git, and Vim, then configuring SSH to use the built-in Windows PowerShell 5 as the default shell.

## Install

Run from PowerShell:

```powershell
irm https://raw.githubusercontent.com/mesotron7x/toolkit/main/install-windows-devbox.ps1 | iex
```

The script accepts UAC elevation and can be re-run safely.

## What it does

- Installs the Windows `OpenSSH.Server~~~~0.0.1.0` optional feature.
- Starts the `sshd` service and sets it to start automatically.
- Enables or creates the Windows Defender Firewall rule for TCP/22.
- Installs Google Chrome through winget.
- Installs Scoop.
- Installs Git and Vim through Scoop.
- Sets the OpenSSH default shell to the built-in Windows PowerShell 5.
- Creates `C:\ProgramData\ssh\administrators_authorized_keys` and applies strict permissions.
- Relaunches itself with UAC elevation when needed.

## Optional flags

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/mesotron7x/toolkit/main/install-windows-devbox.ps1))) -SkipFirewall
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/mesotron7x/toolkit/main/install-windows-devbox.ps1))) -SkipChrome
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/mesotron7x/toolkit/main/install-windows-devbox.ps1))) -SkipScoopTools
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/mesotron7x/toolkit/main/install-windows-devbox.ps1))) -SkipAdminAuthorizedKeys
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

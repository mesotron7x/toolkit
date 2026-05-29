# toolkit

A small collection of practical development utilities and setup scripts.

This repository currently provides two bootstrap tools:

- `install-windows-devbox.ps1` for Windows development hosts.
- `install-ubuntu-devbox.sh` for Ubuntu development hosts.

## Windows devbox

The Windows script makes a fresh Windows development host easier to access and use from a terminal by installing OpenSSH Server, Google Chrome, Scoop, Git, and Vim, then configuring SSH to use the built-in Windows PowerShell 5 as the default shell.

Run from PowerShell:

```powershell
irm https://raw.githubusercontent.com/mesotron7x/toolkit/main/install-windows-devbox.ps1 | iex
```

The script accepts UAC elevation and can be re-run safely.

### What it does

- Installs the Windows `OpenSSH.Server~~~~0.0.1.0` optional feature.
- Starts the `sshd` service and sets it to start automatically.
- Enables or creates the Windows Defender Firewall rule for TCP/22.
- Installs Google Chrome through winget.
- Installs Scoop.
- Installs Git and Vim through Scoop.
- Sets the OpenSSH default shell to the built-in Windows PowerShell 5.
- Creates `C:\ProgramData\ssh\administrators_authorized_keys` and applies strict permissions.
- Relaunches itself with UAC elevation when needed.

### Optional flags

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/mesotron7x/toolkit/main/install-windows-devbox.ps1))) -SkipFirewall
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/mesotron7x/toolkit/main/install-windows-devbox.ps1))) -SkipChrome
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/mesotron7x/toolkit/main/install-windows-devbox.ps1))) -SkipScoopTools
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/mesotron7x/toolkit/main/install-windows-devbox.ps1))) -SkipAdminAuthorizedKeys
```

## Ubuntu devbox

The Ubuntu script bootstraps an Ubuntu 22.04 or newer development host with common CLI tools and opinionated shell/editor configuration.

Run from an existing non-root sudo-capable account:

```bash
curl -fsSL https://raw.githubusercontent.com/mesotron7x/toolkit/main/install-ubuntu-devbox.sh | bash
```

To include Git identity information in the generated `~/.gitconfig`, pass environment variables before running the script:

```bash
curl -fsSL https://raw.githubusercontent.com/mesotron7x/toolkit/main/install-ubuntu-devbox.sh | \
  GIT_USER_NAME="Your Name" GIT_USER_EMAIL="you@example.com" bash
```

The script can also set a custom Git LFS URL:

```bash
curl -fsSL https://raw.githubusercontent.com/mesotron7x/toolkit/main/install-ubuntu-devbox.sh | \
  GIT_LFS_URL="https://example.com/path/to/lfs" bash
```

### What it does

- Verifies that the host is Ubuntu 22.04 or newer.
- Installs `ca-certificates`, `curl`, `git`, `git-lfs`, `sudo`, `tmux`, and `vim` through `apt-get`.
- Writes `~/.gitconfig` with color output, Vim as the editor, `main` as the default initial branch, fast-forward-only pulls, and Git LFS filters.
- Optionally writes Git `user.name`, `user.email`, and Git LFS URL from environment variables.
- Writes `~/.tmux.conf` with a compact status line, large history, stable window names, true-color terminal overrides, and PageUp/PageDown bindings.
- Writes `~/.vimrc` with common editing defaults.
- Adds a passwordless sudoers entry for the invoking non-root user under `/etc/sudoers.d/` after validating it with `visudo`.

## Safety note

The `irm ... | iex` and `curl ... | bash` patterns are convenient, but they execute remote code immediately. For a more auditable flow, download the script first, inspect it, and then run it.

Windows:

```powershell
irm https://raw.githubusercontent.com/mesotron7x/toolkit/main/install-windows-devbox.ps1 -OutFile install-windows-devbox.ps1
notepad .\install-windows-devbox.ps1
powershell -ExecutionPolicy Bypass -File .\install-windows-devbox.ps1
```

Ubuntu:

```bash
curl -fsSLO https://raw.githubusercontent.com/mesotron7x/toolkit/main/install-ubuntu-devbox.sh
less ./install-ubuntu-devbox.sh
bash ./install-ubuntu-devbox.sh
```

## Language policy

Repository content should be written in English by default. Chinese should only be used when it is strictly necessary for a specific user environment, command output, or localized documentation context.

## License

No license has been declared yet.

# Security Review (2026-05-27)

Reviewed repository scripts and related usage docs with focus on command execution, privilege escalation, and network exposure.

## Scope

- `install-windows-sshd.ps1`
- `README.md` usage instructions
- `docs/index.html` usage snippet

## Findings

### 1) Remote code execution pattern (`irm ... | iex`) (High)

The primary install command in both script comments and docs uses `irm <url> | iex`, which executes code fetched at runtime without pinning or integrity verification.

Risk:
- If the source account/repository/branch is compromised, users execute attacker-controlled code.
- If DNS/TLS trust is subverted, this can become an RCE vector.

Current mitigations:
- README/docs include a safety note recommending download + inspection before execution.

Recommendation:
- Make the safer flow the default command in docs.
- Provide a pinned/tagged URL option instead of `main`.
- Optionally publish checksums/signatures for release artifacts.

### 2) Elevated execution with ExecutionPolicy Bypass (Medium)

`Restart-Elevated` relaunches PowerShell with `-ExecutionPolicy Bypass` and then executes remote script content.

Risk:
- Reduces policy-based guardrails.
- Combined with Finding #1, elevates potential impact to admin context.

Recommendation:
- Download to a temporary file and execute with `-File` in the elevated process.
- Validate source content (hash/signature) prior to elevation when feasible.

### 3) Network exposure by opening inbound TCP/22 (Medium)

The script enables/creates firewall rule for inbound SSH on all profiles (`-Profile Any`).

Risk:
- Broadens attack surface, especially on public/untrusted networks.

Recommendation:
- Default to narrower profiles (e.g., Domain,Private) and require explicit opt-in for Public.
- Consider optional source IP restriction guidance.

### 4) Branch-tracking installer URL (`main`) (Low/Medium)

Installer URL points to `main`, not immutable version.

Risk:
- Behavior can change over time; users may run unexpected version.

Recommendation:
- Offer version-pinned URL examples (tag/commit SHA).

## Positive observations

- Uses `Set-StrictMode -Version Latest` and `$ErrorActionPreference = "Stop"`.
- Performs OS and admin checks before privileged operations.
- Idempotent behavior around capability/service/firewall setup lowers accidental misconfiguration risk.

## Overall assessment

The script is functional and reasonably defensive for operational reliability, but the highest security concern is the remote execution pattern (`irm | iex`) combined with elevated execution. The most impactful improvement is switching documentation and elevation flow to **download, inspect/verify, then execute local file**.

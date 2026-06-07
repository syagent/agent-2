# Security Policy

## Reporting a Vulnerability

Do not publish suspected vulnerabilities, credentials, collector tokens, or
host telemetry in a public issue.

Report vulnerabilities privately through the GitHub repository's Security
Advisories page. Include the affected version, reproduction steps, impact, and
any suggested remediation. If private reporting is unavailable, contact the
SyAgent maintainers through the support channel listed on the SyAgent website
and request a private security contact.

## Installation Trust

SyAgent releases are immutable, versioned artifacts. Administrators should:

1. Download `install.sh` and `SHA256SUMS` from the same explicit release.
2. Verify the installer checksum before executing it.
3. Verify `SHA256SUMS.asc` when a trusted SyAgent signing key is available.
4. Pass the same explicit version to the installer.

The installer downloads the remaining files from that release and refuses to
install files that do not match `SHA256SUMS`. It never downloads executable
content from the `main` branch.

A checksum alone detects accidental corruption and mismatched artifacts. It
does not establish publisher identity if an attacker can replace both the
artifact and checksum. Detached signatures provide that additional property
only when the signing key was obtained and trusted through a separate channel.

## Privilege Model

Root is required only to create the dedicated account, install root-owned
files, and configure systemd or cron. Collection runs as the unprivileged
`syAgent` account.

The runtime user can write only its state and log directories. It cannot modify
the installed executable, systemd units, version marker, or token. The systemd
service removes Linux capabilities, prevents privilege escalation, protects
system and kernel configuration, provides a private temporary directory, and
limits network socket families.

Some telemetry is available only when the operating system permits the
unprivileged account to read it. The installer does not grant extra privileges
to bypass host log, process, GPU, or kernel-data permissions.

## Credential Handling

The collector token is stored at `/etc/syAgent/sa-auth.log`, owned by root and
readable by the agent's primary group. It is not written to systemd or cron
configuration.

Interactive installation reads the token without terminal echo. For automation,
prefer a root-readable token file or standard input. Positional tokens are
deprecated because shells and process supervisors may retain command arguments.

During collection, the request body is written to a mode-`0600` temporary file
in `/var/lib/syAgent`, passed to the HTTPS client by filename, and removed when
the agent exits. Diagnostic modes redact the token. Administrators should still
treat agent state, memory, and privileged debugging output as sensitive.

## Network Behavior

The agent makes outbound HTTPS requests to:

- GitHub release URLs during installation or administrator-initiated upgrades
- `https://agent.syagent.com/agent` during collection

Certificate verification is mandatory. Certificate, DNS, connection, timeout,
HTTP, checksum, and signature failures fail closed. The agent has no inbound
listener and no automatic update mechanism.

## Telemetry and Privacy

The payload can contain hostnames, IP addresses, operating-system usernames,
process and application names, installed software versions, GPU process
details, and aggregate SSH authentication-event counts. Review the full table
in `README.md` before installation.

`--print-telemetry` displays the current payload locally with the token redacted.
Its output is sensitive and should not be attached to public bug reports without
review and redaction.

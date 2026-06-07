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

1. Obtain the release-key fingerprint through the SyAgent dashboard or SyAgent
   website security page, independently of GitHub.
2. Download the public key, `install.sh`, `SHA256SUMS`, and `SHA256SUMS.asc`
   from the same explicit release.
3. Confirm the public-key fingerprint is exactly
   `8174245629A3C612E8797E0304E952757DA5F0B2`.
4. Verify the signature and installer checksum before executing the installer.
5. Pass the same explicit version to the installer.

The installer embeds the same public key and fingerprint. It downloads the
signature automatically, verifies it in an isolated temporary GPG home, and
refuses to process checksums signed by any other key. It then refuses to install
files that do not match the authenticated `SHA256SUMS`. It never downloads
executable content from the `main` branch.

A checksum alone does not establish publisher identity if an attacker can
replace both the artifact and checksum. Mandatory signatures address this only
when the pinned fingerprint is also confirmed through a separate SyAgent
channel before the initial installer is executed.

## Release Key Management

The dedicated release private key must remain outside this repository and be
available only to the protected release environment. The repository contains
only the armored public key and full fingerprint.

To rotate the key, first publish an installer release containing both old and
new public keys and fingerprints, with `SHA256SUMS` signed by the old key. After
that release is broadly available, releases may be signed by the new key. The
old key may be removed from a later installer release. A lost or compromised
key requires an explicit incident response and independent redistribution of
the replacement fingerprint.

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
to bypass host log, process, GPU, or kernel-data permissions. In particular,
`ProtectKernelLogs=true` and normal authentication-log permissions commonly
cause SSH success/failure counters to remain zero; collection continues.

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

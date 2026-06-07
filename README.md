# SyAgent System Monitoring Agent

SyAgent is a Bash-based Linux monitoring agent. It runs as a dedicated
unprivileged user, collects host telemetry once per minute, and sends it to the
SyAgent collector over HTTPS.

## Security Model

- Releases are installed by an explicit version, never from the mutable `main`
  branch.
- Release files are verified against `SHA256SUMS` before installation.
- Detached GPG verification is supported when the signing key is already
  trusted by the administrator.
- TLS certificate verification is mandatory for downloads and telemetry.
- The agent runs as `syAgent`; it does not run as root.
- Executables and configuration are owned by root and cannot be modified by
  the runtime user.
- The authentication token is readable only by root and the agent's primary
  group.
- Mutable state and response logs are isolated under `/var/lib/syAgent` and
  `/var/log/syAgent`.
- systemd hosts use a sandboxed oneshot service and timer. Other hosts use a
  dedicated-user cron entry.
- Updates are never installed automatically.

See [SECURITY.md](SECURITY.md) for the threat model, verification details, and
vulnerability reporting guidance.

## Verified Installation

Choose a published release version and download the installer and checksums:

```zsh
VERSION="1.1.0"
BASE_URL="https://github.com/syagent/agent-2/releases/download/v${VERSION}"

curl --fail --location --proto '=https' --tlsv1.2 \
  --output install.sh "${BASE_URL}/install.sh"
curl --fail --location --proto '=https' --tlsv1.2 \
  --output SHA256SUMS "${BASE_URL}/SHA256SUMS"

grep ' install.sh$' SHA256SUMS | sha256sum --check --strict -
chmod +x install.sh
sudo ./install.sh --version "$VERSION"
```

On systems without `sha256sum`, use:

```zsh
grep ' install.sh$' SHA256SUMS | shasum --algorithm 256 --check -
```

The installer prompts for the token without echoing it. Automation can provide
the token through a protected file or standard input:

```zsh
sudo ./install.sh --version "$VERSION" --token-file /root/syagent-token
```

```zsh
printf '%s\n' "$SYAGENT_TOKEN" |
  sudo ./install.sh --version "$VERSION" --token-stdin
```

A positional token remains supported for compatibility, but it can be recorded
in shell history and should be avoided.

### Optional GPG Verification

If the SyAgent release signing key is already trusted in the local GPG keyring,
download the detached signature and verify it before installation:

```zsh
curl --fail --location --proto '=https' --tlsv1.2 \
  --output SHA256SUMS.asc "${BASE_URL}/SHA256SUMS.asc"
gpg --verify SHA256SUMS.asc SHA256SUMS
sudo ./install.sh --version "$VERSION" --signature-file SHA256SUMS.asc
```

Checksum verification protects against corrupted or mismatched downloads. GPG
verification additionally authenticates the checksum file through a separately
trusted signing key.

## Installation Layout

| Path | Ownership/mode | Purpose |
| --- | --- | --- |
| `/etc/syAgent/sh-agent.sh` | `root:root`, `0755` | Agent executable |
| `/etc/syAgent/uninstall.sh` | `root:root`, `0755` | Scoped uninstaller |
| `/etc/syAgent/sa-auth.log` | `root:<agent-group>`, `0640` | Authentication token |
| `/etc/syAgent/VERSION` | `root:root`, `0644` | Installed release |
| `/var/lib/syAgent` | `syAgent:<agent-group>`, `0750` | Mutable counter state |
| `/var/log/syAgent` | `syAgent:<agent-group>`, `0750` | Collector response/cron logs |
| `/etc/systemd/system/syagent.*` | `root:root`, `0644` | systemd runtime units |

## Collected Telemetry

The following data is collected on every run when available. These defaults are
unchanged from the existing agent payload.

### Host and Operating System

- Agent version, uptime, kernel, distribution, architecture, hostname, and
  timezone
- CPU model, vendor, architecture, core/thread count, socket count, current,
  minimum, and maximum frequency
- Virtualization/container type, detected cloud vendor, package manager, boot
  mode, reboot-required state, and whether a machine ID exists
- Active login-session count, process count, open file handles, and file-handle
  limit

### Memory and CPU

- Total/used RAM and total/used swap
- Available, free, buffered, cached, active, inactive, anonymous, slab,
  reclaimable, shared, dirty, writeback, page-table, kernel-stack, commit-limit,
  and committed memory
- Memory PSI averages, page faults, major faults, swap activity, page scans,
  page reclamation, and OOM-kill deltas
- Load averages, CPU utilization, and I/O-wait utilization

### Storage and RAID

- Mounted device names, capacity, and usage
- Per-device read/write throughput, IOPS, busy percentage, and cumulative bytes
- Linux software RAID, LVM, encrypted-device, and device-mapper RAID summaries

### Network

- Selected network-interface name
- Host IPv4 and IPv6 addresses
- Active TCP/UDP connection count
- Received/transmitted byte counters and interval deltas

### Processes, Applications, and GPU

- Up to 15 top processes, including operating-system username, CPU usage, RSS,
  and command name
- Installed versions of detected web servers, databases, language runtimes,
  compilers, package managers, container tools, orchestration tools, proxies,
  certificate tools, process managers, and firewall/security tools
- NVIDIA GPU model, utilization, memory usage, and temperature
- NVIDIA compute-process GPU UUID, PID, operating-system username, process
  name, and used memory

### SSH

- Aggregate counts of accepted and failed password/public-key events readable
  from `/var/log/auth.log` or `/var/log/secure`
- Log message bodies, passwords, and key material are not transmitted

The token and payload are form encoded for the existing collector API. Base64
inside the payload is encoding, not encryption; confidentiality is provided by
verified HTTPS.

## Operations

Check the local installation and required commands:

```zsh
sudo -u syAgent /etc/syAgent/sh-agent.sh --check
```

Print the current payload without sending it or exposing the token:

```zsh
sudo -u syAgent /etc/syAgent/sh-agent.sh --print-telemetry
```

The output intentionally contains collected host telemetry but replaces the
credential with `token=[REDACTED]`.

Check systemd status and logs:

```zsh
sudo systemctl status syagent.timer syagent.service
sudo journalctl --unit syagent.service
```

On cron fallback installations:

```zsh
sudo crontab -u syAgent -l
sudo tail /var/log/syAgent/cron.log
```

Install a newer release by downloading and verifying its installer, then run it
with the new explicit version. Existing releases never update themselves.

## Uninstallation

```zsh
sudo /etc/syAgent/uninstall.sh
```

The uninstaller removes only the SyAgent service/timer, SyAgent cron entry,
installed files, runtime state/logs, and dedicated user.

## Requirements

- Linux
- Root privileges for installation and uninstallation
- Bash and standard Linux utilities
- `curl` or `wget` for installation; `wget` for the installed agent
- `sha256sum` or `shasum`
- systemd, or cron as a fallback

## Release Packaging

Maintainers can produce release assets locally:

```zsh
./scripts/build-release.sh 1.1.0
```

Set `GPG_KEY_ID` to create `SHA256SUMS.asc` with an existing signing key:

```zsh
GPG_KEY_ID="SIGNING_KEY_FINGERPRINT" ./scripts/build-release.sh 1.1.0
```

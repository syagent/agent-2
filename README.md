# SyAgent - System Monitoring Agent

SyAgent is a lightweight, comprehensive system monitoring agent written in Bash that collects detailed system metrics and securely transmits them to the SyAgent monitoring service. It provides real-time visibility into your server's performance, resource usage, and system health.

## Features

- **Comprehensive Monitoring**: Tracks CPU, memory, disk, network, GPU, and process metrics
- **Lightweight**: Pure Bash implementation with minimal system overhead
- **Secure**: Token-based authentication for data transmission
- **Easy Installation**: One-command setup with automatic dependency management
- **Cross-Platform**: Supports major Linux distributions (Ubuntu, CentOS, Arch, etc.)
- **Real-time**: Collects and reports metrics every minute via cron

## Quick Start

### Installation

1. **Get your authentication token** from the SyAgent dashboard
2. **Run the installer** as root:

```bash
curl -sSL https://raw.githubusercontent.com/syagent/agent-2/main/install.sh | bash -s 'YOUR_TOKEN_HERE'
```

Alternatively, download and run manually:

```bash
wget https://raw.githubusercontent.com/syagent/agent-2/main/install.sh
chmod +x install.sh
sudo ./install.sh 'YOUR_TOKEN_HERE'
```

### What the installer does:

- Downloads the monitoring agent to `/etc/syAgent/`
- Creates a dedicated `syAgent` user for security
- Sets up a cron job to run every minute
- Installs cron if not already present
- Configures proper permissions and security settings

## Requirements

- **Operating System**: Linux (any modern distribution)
- **Permissions**: Root access for installation (agent runs as dedicated user)
- **Dependencies**: 
  - `bash` (installed by default on most systems)
  - `cron` (auto-installed if missing)
  - `wget` or `curl` (for installation and data transmission)
  - Standard system utilities (`ps`, `df`, `who`, etc.)

## Monitored Metrics

### System
- System uptime
- System load average
- IO load and wait times

### Operating System
- OS kernel version
- OS name and distribution
- System architecture (x64, x86, ARM, etc.)

### CPU
- CPU identifier and model
- Number of CPU cores
- CPU frequency
- Real-time CPU load percentage

### Memory
- RAM total capacity
- RAM usage (used/free)
- SWAP total capacity  
- SWAP usage statistics

### Storage
- Disk list and mount points
- Total disk capacity
- Disk usage per partition
- Available free space

### Network
- Active connection count
- Network interface identifiers
- IPv4 and IPv6 addresses
- RX/TX bytes since boot
- Current RX/TX transfer rates

### Processes
- Total process count
- Process list with CPU/memory usage
- Top processes by resource consumption

### File System
- Open file handle count
- System file handle limits

### GPU (NVIDIA)
- GPU identifier and model
- GPU memory total/usage
- GPU utilization percentage
- GPU temperature
- Running GPU processes

### Applications
- Installed application versions
- Running services and daemons
- Database versions (MySQL, PostgreSQL, MongoDB, Redis)
- Web server versions (Apache, Nginx)
- Programming language versions (Python, Node.js, Java, etc.)

### SSH & Security
- SSH connection attempts (successful/failed)
- Login session count
- Security event monitoring

### Miscellaneous
- Agent version
- Active user sessions
- System configuration details

## Configuration

The agent stores its configuration in `/etc/syAgent/`:

- `sa-auth.log`: Contains your authentication token
- `sh-agent.sh`: The main monitoring script
- `sh-cron.log`: Execution logs from cron
- `sh-agent.log`: Data transmission logs

## Troubleshooting

### Check if the agent is running:
```bash
sudo crontab -u syAgent -l
```

### View recent logs:
```bash
sudo tail -f /etc/syAgent/sh-cron.log
```

### Manual test run:
```bash
sudo -u syAgent bash /etc/syAgent/sh-agent.sh
```

### Reinstall the agent:
```bash
# The installer automatically removes old installations
sudo ./install.sh 'YOUR_TOKEN_HERE'
```

## Uninstallation

To remove SyAgent completely:

```bash
# Remove cron job
sudo crontab -u syAgent -r 2>/dev/null
# Remove user
sudo userdel syAgent 2>/dev/null
# Remove files
sudo rm -rf /etc/syAgent
```

## Security

- Agent runs as a dedicated non-privileged user (`syAgent`)
- Secure token-based authentication
- HTTPS encryption for all data transmission
- No sensitive data stored locally except authentication token
- Minimal system permissions required for operation

## Contributing

We welcome contributions! Please feel free to submit issues, feature requests, or pull requests.

## License

This project is open source. Please check the repository for license details.

## Support

- **Issues**: Report bugs or request features via GitHub issues
- **Documentation**: Visit the SyAgent dashboard for detailed setup guides
- **Community**: Join our community forums for tips and support

---

**Version**: 1.0.9  
**Compatibility**: Linux (Ubuntu, CentOS, Debian, Arch, RHEL, and more)

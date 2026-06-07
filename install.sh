#!/bin/bash
# @version 1.1.0

set -Eeuo pipefail
umask 027

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
readonly PATH

readonly REPOSITORY="syagent/agent-2"
readonly CONFIG_DIR="/etc/syAgent"
readonly STATE_DIR="/var/lib/syAgent"
readonly LOG_DIR="/var/log/syAgent"
readonly SYSTEMD_DIR="/etc/systemd/system"
readonly AGENT_USER="syAgent"

release_version=""
token=""
token_file=""
read_token_stdin=false
signature_file=""
positional_token_used=false
staging_dir=""
backup_dir=""
install_committed=false
config_replaced=false

usage() {
  cat <<'EOF'
Usage:
  sudo ./install.sh --version VERSION [--token-file PATH]
  printf '%s' "$SYAGENT_TOKEN" | sudo ./install.sh --version VERSION --token-stdin

Options:
  --version VERSION       Install a pinned GitHub release (for example, 1.1.0).
  --token-file PATH       Read the token from a file.
  --token-stdin           Read the token from standard input.
  --signature-file PATH   Verify SHA256SUMS with this detached GPG signature.
  -h, --help              Show this help.

A positional token is temporarily supported for compatibility, but it may be
stored in shell history. Prefer the hidden prompt, --token-file, or --token-stdin.
EOF
}

log() {
  printf '%s\n' "$*"
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  local exit_code=$?

  if [ "$install_committed" = false ] && [ "$config_replaced" = true ]; then
    rm -rf "$CONFIG_DIR"
    if [ -n "$backup_dir" ] && [ -d "$backup_dir" ]; then
      mv "$backup_dir" "$CONFIG_DIR"
    fi
  fi

  if [ -n "$staging_dir" ] && [ -d "$staging_dir" ]; then
    rm -rf "$staging_dir"
  fi

  if [ "$install_committed" = true ] && [ -n "$backup_dir" ] && [ -d "$backup_dir" ]; then
    rm -rf "$backup_dir"
  fi

  exit "$exit_code"
}

trap cleanup EXIT

validate_version() {
  case "$release_version" in
    v*) release_version="${release_version#v}" ;;
  esac

  case "$release_version" in
    "" | *[!A-Za-z0-9._-]*) fail "invalid release version: $release_version" ;;
  esac
}

read_token() {
  if [ -n "$token_file" ]; then
    [ -f "$token_file" ] || fail "token file does not exist: $token_file"
    token="$(cat "$token_file")"
  elif [ "$read_token_stdin" = true ]; then
    token="$(cat)"
  elif [ -z "$token" ]; then
    [ -r /dev/tty ] || fail "no token source provided; use --token-file or --token-stdin"
    printf 'SyAgent token: ' >/dev/tty
    IFS= read -r -s token </dev/tty || true
    printf '\n' >/dev/tty
  fi

  [ -n "$token" ] || fail "the authentication token cannot be empty"
  [ "${#token}" -le 4096 ] || fail "the authentication token is unexpectedly long"

  case "$token" in
    *$'\n'* | *$'\r'*) fail "the authentication token must be a single line" ;;
  esac
}

download_file() {
  local url="$1"
  local destination="$2"

  if command -v curl >/dev/null 2>&1; then
    curl --fail --silent --show-error --location \
      --proto '=https' --tlsv1.2 \
      --connect-timeout 15 --max-time 120 \
      --output "$destination" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget --https-only --timeout=30 --tries=2 --output-document="$destination" "$url"
  else
    fail "curl or wget is required"
  fi

  [ -s "$destination" ] || fail "downloaded file is empty: $url"
}

verify_checksum() {
  local checksum_file="$1"
  local artifact="$2"
  local artifact_name

  artifact_name="$(basename "$artifact")"

  if command -v sha256sum >/dev/null 2>&1; then
    (
      cd "$(dirname "$artifact")"
      grep -E "^[[:xdigit:]]{64}[[:space:]]+[* ]?${artifact_name}$" "$checksum_file" |
        sha256sum --check --strict -
    ) || fail "checksum verification failed for $artifact_name"
  elif command -v shasum >/dev/null 2>&1; then
    (
      cd "$(dirname "$artifact")"
      grep -E "^[[:xdigit:]]{64}[[:space:]]+[* ]?${artifact_name}$" "$checksum_file" |
        shasum --algorithm 256 --check -
    ) || fail "checksum verification failed for $artifact_name"
  else
    fail "sha256sum or shasum is required for release verification"
  fi
}

remove_agent_cron() {
  local cron_user="$1"
  local existing_cron

  command -v crontab >/dev/null 2>&1 || return 0
  id -u "$cron_user" >/dev/null 2>&1 || return 0

  existing_cron="$(crontab -u "$cron_user" -l 2>/dev/null || true)"
  printf '%s\n' "$existing_cron" |
    grep -v -F "/etc/syAgent/sh-agent.sh" |
    crontab -u "$cron_user" -
}

install_systemd_runtime() {
  install -o root -g root -m 0644 "$CONFIG_DIR/syagent.service" "$SYSTEMD_DIR/syagent.service"
  install -o root -g root -m 0644 "$CONFIG_DIR/syagent.timer" "$SYSTEMD_DIR/syagent.timer"

  remove_agent_cron "$AGENT_USER"
  systemctl daemon-reload
  systemctl enable --now syagent.timer
  log "Runtime: systemd timer"
}

install_cron_runtime() {
  local existing_cron

  command -v crontab >/dev/null 2>&1 ||
    fail "systemd is unavailable and crontab is not installed"

  existing_cron="$(crontab -u "$AGENT_USER" -l 2>/dev/null || true)"
  {
    printf '%s\n' "$existing_cron" | grep -v -F "/etc/syAgent/sh-agent.sh"
    printf '%s\n' "*/1 * * * * /bin/bash /etc/syAgent/sh-agent.sh >> /var/log/syAgent/cron.log 2>&1"
  } | crontab -u "$AGENT_USER" -

  log "Runtime: cron"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      [ "$#" -ge 2 ] || fail "--version requires a value"
      release_version="$2"
      shift 2
      ;;
    --token-file)
      [ "$#" -ge 2 ] || fail "--token-file requires a path"
      token_file="$2"
      shift 2
      ;;
    --token-stdin)
      read_token_stdin=true
      shift
      ;;
    --signature-file)
      [ "$#" -ge 2 ] || fail "--signature-file requires a path"
      signature_file="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --*)
      fail "unknown option: $1"
      ;;
    *)
      [ -z "$token" ] || fail "only one positional token is supported"
      token="$1"
      positional_token_used=true
      shift
      ;;
  esac
done

[ "$(id -u)" -eq 0 ] || fail "run the installer as root"
[ "$(uname -s)" = "Linux" ] || fail "SyAgent currently supports Linux only"
[ -n "$release_version" ] || fail "--version is required"
[ -z "$token_file" ] || [ "$read_token_stdin" = false ] ||
  fail "--token-file and --token-stdin cannot be used together"
[ -z "$token" ] || { [ -z "$token_file" ] && [ "$read_token_stdin" = false ]; } ||
  fail "a positional token cannot be combined with another token source"

validate_version
read_token

if [ "$positional_token_used" = true ]; then
  log "Warning: positional tokens may be stored in shell history."
fi

command -v wget >/dev/null 2>&1 ||
  fail "wget is required by the installed monitoring agent"

release_tag="v${release_version}"
release_base="https://github.com/${REPOSITORY}/releases/download/${release_tag}"
staging_dir="$(mktemp -d "${CONFIG_DIR}.install.XXXXXX")"
checksum_file="$staging_dir/SHA256SUMS"

log "Downloading SyAgent ${release_version} release artifacts..."
download_file "$release_base/SHA256SUMS" "$checksum_file"

if [ -n "$signature_file" ]; then
  command -v gpg >/dev/null 2>&1 || fail "gpg is required for signature verification"
  [ -f "$signature_file" ] || fail "signature file does not exist: $signature_file"
  gpg --verify "$signature_file" "$checksum_file" ||
    fail "SHA256SUMS signature verification failed"
fi

for artifact_name in sh-agent.sh uninstall.sh syagent.service syagent.timer; do
  download_file "$release_base/$artifact_name" "$staging_dir/$artifact_name"
  verify_checksum "$checksum_file" "$staging_dir/$artifact_name"
done

bash -n "$staging_dir/sh-agent.sh"
bash -n "$staging_dir/uninstall.sh"

if ! id -u "$AGENT_USER" >/dev/null 2>&1; then
  nologin_shell="/usr/sbin/nologin"
  [ -x "$nologin_shell" ] || nologin_shell="/bin/false"
  useradd --system --home-dir "$STATE_DIR" --shell "$nologin_shell" "$AGENT_USER"
fi
agent_group="$(id -gn "$AGENT_USER")"

install -d -o "$AGENT_USER" -g "$agent_group" -m 0750 "$STATE_DIR" "$LOG_DIR"
install -o root -g root -m 0755 "$staging_dir/sh-agent.sh" "$staging_dir/installed-sh-agent.sh"
install -o root -g root -m 0755 "$staging_dir/uninstall.sh" "$staging_dir/installed-uninstall.sh"
printf '%s\n' "$token" > "$staging_dir/sa-auth.log"
printf '%s\n' "$release_version" > "$staging_dir/VERSION"
chown root:"$agent_group" "$staging_dir/sa-auth.log"
chmod 0640 "$staging_dir/sa-auth.log"
chown root:root "$staging_dir/VERSION"
chmod 0644 "$staging_dir/VERSION"

rm -f "$staging_dir/sh-agent.sh" "$staging_dir/uninstall.sh"
mv "$staging_dir/installed-sh-agent.sh" "$staging_dir/sh-agent.sh"
mv "$staging_dir/installed-uninstall.sh" "$staging_dir/uninstall.sh"
rm -f "$staging_dir/SHA256SUMS"
chown root:root "$staging_dir"
chmod 0755 "$staging_dir"

if [ -e "$CONFIG_DIR" ]; then
  backup_dir="${CONFIG_DIR}.backup.$$"
  mv "$CONFIG_DIR" "$backup_dir"
fi
mv "$staging_dir" "$CONFIG_DIR"
staging_dir=""
config_replaced=true

if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  install_systemd_runtime
else
  install_cron_runtime
fi

install_committed=true
token=""

log "SyAgent ${release_version} installed successfully."
log "Configuration: $CONFIG_DIR"
log "State: $STATE_DIR"
log "Logs: $LOG_DIR"

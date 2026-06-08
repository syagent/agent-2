#!/bin/bash
# @version 1.2.0

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
readonly TRUSTED_RELEASE_FINGERPRINTS="8174245629A3C612E8797E0304E952757DA5F0B2"

release_version=""
token=""
token_file=""
read_token_stdin=false
positional_token_used=false
staging_dir=""
backup_dir=""
install_committed=false
config_replaced=false
current_step="initialization"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != "dumb" ]; then
  readonly GREEN=$'\033[32m'
  readonly RESET=$'\033[0m'
else
  readonly GREEN=""
  readonly RESET=""
fi

if [ -t 2 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != "dumb" ]; then
  readonly RED=$'\033[31m'
else
  readonly RED=""
fi

usage() {
  cat <<'EOF'
Usage:
  sudo ./install.sh TOKEN
  sudo ./install.sh --version VERSION [--token-file PATH]
  printf '%s' "$SYAGENT_TOKEN" | sudo ./install.sh --version VERSION --token-stdin

Options:
  --version VERSION       Install a pinned, signed GitHub release.
  --token-file PATH       Read the token from a file.
  --token-stdin           Read the token from standard input.
  -h, --help              Show this help.

A positional token is temporarily supported for compatibility, but it may be
stored in shell history. Prefer the hidden prompt, --token-file, or --token-stdin.
EOF
}

log() {
  printf '%s%s%s\n' "$GREEN" "$*" "$RESET"
}

fail() {
  printf '%sError: %s%s\n' "$RED" "$*" "$RESET" >&2
  exit 1
}

on_error() {
  local exit_code="$1"
  local line_number="$2"

  trap - ERR
  printf '%sError: Installation failed during %s (line %s, exit %s)%s\n' \
    "$RED" "$current_step" "$line_number" "$exit_code" "$RESET" >&2
  exit "$exit_code"
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

trap 'on_error $? $LINENO' ERR
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
  local artifact_name

  artifact_name="$(basename "$destination")"

  if command -v wget >/dev/null 2>&1; then
    if ! wget --https-only --timeout=30 --tries=2 --quiet \
      --output-document="$destination" "$url"; then
      fail "could not download $artifact_name from $url"
    fi
  elif command -v curl >/dev/null 2>&1; then
    if ! curl --fail --silent --show-error --location \
      --proto '=https' --tlsv1.2 \
      --connect-timeout 15 --max-time 60 \
      --output "$destination" "$url"; then
      fail "could not download $artifact_name from $url"
    fi
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

write_release_public_keys() {
  cat >"$1" <<'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mDMEaiV1qBYJKwYBBAHaRw8BAQdAbGTndJ9L5sSNdsOG9Yv4Li8db3CnnTW9KPni
k+inDLS0LlN5QWdlbnQgUmVsZWFzZSBTaWduaW5nIDxyZWxlYXNlc0BzeWFnZW50
LmNvbT6ImQQTFgoAQRYhBIF0JFYpo8YS6Hl+AwTpUnV9pfCyBQJqJXWoAhsDBQkF
o5qABQsJCAcCAiICBhUKCQgLAgQWAgMBAh4HAheAAAoJEATpUnV9pfCyxmoBAI4Z
XUVWLc8+EcaxBkf3K6uuEgm7X1fT1MeIgQujT3LeAP4iaLinRaC3q4JnREL5eRtC
3T50bw0lMPGgg7SMgN36DA==
=y0US
-----END PGP PUBLIC KEY BLOCK-----
EOF
}

fingerprint_is_trusted() {
  local candidate="$1"
  local trusted_fingerprint

  for trusted_fingerprint in $TRUSTED_RELEASE_FINGERPRINTS; do
    if [ "$candidate" = "$trusted_fingerprint" ]; then
      return 0
    fi
  done

  return 1
}

verify_release_signature() {
  local checksum_file="$1"
  local signature_file="$2"
  local public_key_file="$staging_dir/release-signing-keys.asc"
  local gpg_home="$staging_dir/gnupg"
  local status_file="$staging_dir/gpg-status"
  local fingerprint=""
  local imported_fingerprints=""
  local valid_signature_fingerprint=""

  command -v gpg >/dev/null 2>&1 ||
    fail "gpg is required for mandatory release signature verification"

  mkdir -m 0700 "$gpg_home"
  write_release_public_keys "$public_key_file"

  imported_fingerprints="$(
    gpg --batch --homedir "$gpg_home" --with-colons \
      --import-options show-only --import "$public_key_file" 2>/dev/null |
      awk -F: '$1 == "pub" { want_fpr = 1; next } want_fpr && $1 == "fpr" { print $10; want_fpr = 0 }'
  )"
  [ -n "$imported_fingerprints" ] ||
    fail "embedded release signing key is invalid"

  for fingerprint in $imported_fingerprints; do
    fingerprint_is_trusted "$fingerprint" ||
      fail "embedded release key fingerprint is not trusted: $fingerprint"
  done

  for fingerprint in $TRUSTED_RELEASE_FINGERPRINTS; do
    printf '%s\n' "$imported_fingerprints" | grep -Fx "$fingerprint" >/dev/null ||
      fail "trusted release key is missing from the embedded key bundle: $fingerprint"
  done

  gpg --batch --homedir "$gpg_home" --import "$public_key_file" >/dev/null 2>&1 ||
    fail "could not import the embedded release signing key"

  if ! gpg --batch --homedir "$gpg_home" --status-fd 1 \
    --verify "$signature_file" "$checksum_file" >"$status_file" 2>/dev/null; then
    fail "SHA256SUMS signature verification failed"
  fi

  valid_signature_fingerprint="$(
    awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { print $3; exit }' "$status_file"
  )"
  [ -n "$valid_signature_fingerprint" ] ||
    fail "release signature did not identify a valid signing key"
  fingerprint_is_trusted "$valid_signature_fingerprint" ||
    fail "release was signed by an untrusted key: $valid_signature_fingerprint"
}

remove_agent_cron() {
  local cron_user="$1"
  local existing_cron
  local filtered_cron

  command -v crontab >/dev/null 2>&1 || return 0
  id -u "$cron_user" >/dev/null 2>&1 || return 0

  existing_cron="$(crontab -u "$cron_user" -l 2>/dev/null || true)"
  filtered_cron="$(
    printf '%s\n' "$existing_cron" |
      grep -v -F "/etc/syAgent/sh-agent.sh" || true
  )"

  if [ -n "$filtered_cron" ]; then
    printf '%s\n' "$filtered_cron" | crontab -u "$cron_user" -
  else
    crontab -u "$cron_user" -r 2>/dev/null || true
  fi
}

install_systemd_runtime() {
  install -o root -g root -m 0644 "$CONFIG_DIR/syagent.service" "$SYSTEMD_DIR/syagent.service"
  install -o root -g root -m 0644 "$CONFIG_DIR/syagent.timer" "$SYSTEMD_DIR/syagent.timer"

  remove_agent_cron "$AGENT_USER"
  systemctl daemon-reload
  systemctl enable --now syagent.timer
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
[ -z "$token_file" ] || [ "$read_token_stdin" = false ] ||
  fail "--token-file and --token-stdin cannot be used together"
[ -z "$token" ] || { [ -z "$token_file" ] && [ "$read_token_stdin" = false ]; } ||
  fail "a positional token cannot be combined with another token source"

if [ -n "$release_version" ]; then
  validate_version
fi
read_token

log "Preparing SyAgent installation..."

command -v wget >/dev/null 2>&1 ||
  fail "wget is required by the installed monitoring agent"
staging_dir="$(mktemp -d "${CONFIG_DIR}.install.XXXXXX")"

if [ -n "$release_version" ]; then
  current_step="signed release download"
  command -v gpg >/dev/null 2>&1 ||
    fail "gpg is required for mandatory release signature verification"

  release_tag="v${release_version}"
  release_base="https://github.com/${REPOSITORY}/releases/download/${release_tag}"
  checksum_file="$staging_dir/SHA256SUMS"
  signature_file="$staging_dir/SHA256SUMS.asc"

  download_file "$release_base/SHA256SUMS" "$checksum_file"
  download_file "$release_base/SHA256SUMS.asc" "$signature_file"
  verify_release_signature "$checksum_file" "$signature_file"

  for artifact_name in sh-agent.sh uninstall.sh syagent.service syagent.timer; do
    download_file "$release_base/$artifact_name" "$staging_dir/$artifact_name"
    verify_checksum "$checksum_file" "$staging_dir/$artifact_name"
  done
else
  current_step="main branch download"
  release_version="main"
  release_base="https://raw.githubusercontent.com/${REPOSITORY}/main"

  for artifact_name in sh-agent.sh uninstall.sh syagent.service syagent.timer; do
    download_file "$release_base/$artifact_name" "$staging_dir/$artifact_name"
  done
fi

bash -n "$staging_dir/sh-agent.sh"
bash -n "$staging_dir/uninstall.sh"
current_step="file installation"

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
rm -rf "$staging_dir/SHA256SUMS" "$staging_dir/SHA256SUMS.asc" \
  "$staging_dir/release-signing-keys.asc" "$staging_dir/gpg-status" \
  "$staging_dir/gnupg"
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
  current_step="systemd configuration"
  log "Configuring SyAgent..."
  install_systemd_runtime
else
  current_step="cron configuration"
  log "Configuring SyAgent..."
  install_cron_runtime
fi

install_committed=true
token=""

log "SyAgent installed successfully."

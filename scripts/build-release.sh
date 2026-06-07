#!/bin/bash

set -Eeuo pipefail
umask 022

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
readonly PATH

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:-}"
output_dir="${2:-$repo_dir/dist}"

if [ -z "$version" ]; then
  printf 'Usage: %s VERSION [OUTPUT_DIR]\n' "$0" >&2
  exit 1
fi

case "$version" in
  v*) version="${version#v}" ;;
esac

case "$version" in
  "" | *[!A-Za-z0-9._-]*)
    printf 'Error: invalid version: %s\n' "$version" >&2
    exit 1
    ;;
esac

version_dir="$output_dir/v$version"
mkdir -p "$version_dir"

for artifact in install.sh sh-agent.sh uninstall.sh syagent.service syagent.timer; do
  install -m 0644 "$repo_dir/$artifact" "$version_dir/$artifact"
done
chmod 0755 "$version_dir/install.sh" "$version_dir/sh-agent.sh" "$version_dir/uninstall.sh"

(
  cd "$version_dir"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum install.sh sh-agent.sh uninstall.sh syagent.service syagent.timer >SHA256SUMS
  else
    shasum -a 256 install.sh sh-agent.sh uninstall.sh syagent.service syagent.timer >SHA256SUMS
  fi
)

if [ -n "${GPG_KEY_ID:-}" ]; then
  gpg --batch --yes --local-user "$GPG_KEY_ID" \
    --armor --detach-sign --output "$version_dir/SHA256SUMS.asc" \
    "$version_dir/SHA256SUMS"
fi

printf 'Release artifacts created in %s\n' "$version_dir"

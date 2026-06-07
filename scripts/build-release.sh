#!/bin/bash

set -Eeuo pipefail
umask 022

PATH=/opt/homebrew/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
readonly PATH

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly expected_fingerprint="8174245629A3C612E8797E0304E952757DA5F0B2"
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

command -v gpg >/dev/null 2>&1 || {
  printf 'Error: gpg is required to build a signed release\n' >&2
  exit 1
}

if [ -z "${GPG_KEY_ID:-}" ]; then
  printf 'Error: GPG_KEY_ID must identify the SyAgent release signing key\n' >&2
  exit 1
fi

signing_fingerprint="$(
  gpg --batch --with-colons --fingerprint "$GPG_KEY_ID" 2>/dev/null |
    awk -F: '$1 == "pub" { want_fpr = 1; next } want_fpr && $1 == "fpr" { print $10; exit }'
)"

if [ "$signing_fingerprint" != "$expected_fingerprint" ]; then
  printf 'Error: GPG_KEY_ID resolves to %s, expected %s\n' \
    "${signing_fingerprint:-no key}" "$expected_fingerprint" >&2
  exit 1
fi

gpg --batch --list-secret-keys "$GPG_KEY_ID" >/dev/null 2>&1 || {
  printf 'Error: the configured SyAgent release private key is unavailable\n' >&2
  exit 1
}

public_key_fingerprint="$(
  gpg --batch --with-colons --import-options show-only \
    --import "$repo_dir/release-signing-key.asc" 2>/dev/null |
    awk -F: '$1 == "pub" { want_fpr = 1; next } want_fpr && $1 == "fpr" { print $10; exit }'
)"

if [ "$public_key_fingerprint" != "$expected_fingerprint" ]; then
  printf 'Error: committed release public key has fingerprint %s, expected %s\n' \
    "${public_key_fingerprint:-invalid key}" "$expected_fingerprint" >&2
  exit 1
fi

version_dir="$output_dir/v$version"
mkdir -p "$version_dir"

for artifact in install.sh sh-agent.sh uninstall.sh syagent.service syagent.timer release-signing-key.asc; do
  install -m 0644 "$repo_dir/$artifact" "$version_dir/$artifact"
done
chmod 0755 "$version_dir/install.sh" "$version_dir/sh-agent.sh" "$version_dir/uninstall.sh"

(
  cd "$version_dir"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum install.sh sh-agent.sh uninstall.sh syagent.service syagent.timer release-signing-key.asc >SHA256SUMS
  else
    shasum -a 256 install.sh sh-agent.sh uninstall.sh syagent.service syagent.timer release-signing-key.asc >SHA256SUMS
  fi
)

gpg --batch --yes --local-user "$signing_fingerprint" \
  --armor --detach-sign --output "$version_dir/SHA256SUMS.asc" \
  "$version_dir/SHA256SUMS"

printf 'Release artifacts created in %s\n' "$version_dir"

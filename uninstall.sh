#!/bin/bash

set -Eeuo pipefail

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
readonly PATH

readonly AGENT_USER="syAgent"
readonly CONFIG_DIR="/etc/syAgent"
readonly STATE_DIR="/var/lib/syAgent"
readonly LOG_DIR="/var/log/syAgent"

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

remove_agent_cron() {
  local existing_cron

  command -v crontab >/dev/null 2>&1 || return 0
  id -u "$AGENT_USER" >/dev/null 2>&1 || return 0

  existing_cron="$(crontab -u "$AGENT_USER" -l 2>/dev/null || true)"
  printf '%s\n' "$existing_cron" |
    grep -v -F "/etc/syAgent/sh-agent.sh" |
    crontab -u "$AGENT_USER" -
}

[ "$(id -u)" -eq 0 ] || fail "run the uninstaller as root"

if command -v systemctl >/dev/null 2>&1; then
  systemctl disable --now syagent.timer 2>/dev/null || true
  systemctl stop syagent.service 2>/dev/null || true
fi

remove_agent_cron

rm -f /etc/systemd/system/syagent.service /etc/systemd/system/syagent.timer

if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload
fi

rm -rf "$CONFIG_DIR" "$STATE_DIR" "$LOG_DIR"

if id -u "$AGENT_USER" >/dev/null 2>&1; then
  userdel "$AGENT_USER"
fi

printf '%s\n' "SyAgent has been removed."

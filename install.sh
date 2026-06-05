#!/bin/bash
# @version		1.1.0

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

function printRed() {
	echo -e "\e[31m${*}\e[0m"
}

function printGreen() {
	printf "\e[32m${1}\e[0m"
}

function printBold() {
	printf "\033[1m${1}\033[0m"
}

function fail() {
  printRed "$1"
  exit 1
}

printBold "|\n|   SyAgent Installer\n| =\n|"

if [ "$(id -u)" != "0" ]; then
  fail "|\n| Error: Please run the agent as root\n| \tThe agent will NOT run as root but root required to make the installation success\n|"
fi

SYSTEM="$(uname -s 2> /dev/null || uname -v)"
OS="$(uname -o 2> /dev/null || uname -rs)"
MACHINE="$(uname -m 2> /dev/null)"

printBold "System            : ${SYSTEM}"
printBold "Operating System  : ${OS}"
printBold "Machine           : ${MACHINE}"

if [ $# -lt 1 ]
then
	fail "|\n| Usage: bash $0 'token'\n|"
fi

if [ -z "$(command -v wget)" ]; then
  fail "|\n| Error: wget is required to download the syAgent script\n|"
fi

function answer_yes() {
  [ -z "$1" ] || [ "$1" = "Y" ] || [ "$1" = "y" ]
}

function remove_agent_cron() {
  local cron_user="$1"
  local existing_cron

  existing_cron="$(crontab -u "$cron_user" -l 2>/dev/null || true)"
  printf "%s\n" "$existing_cron" | grep -v "/etc/syAgent/sh-agent.sh" | crontab -u "$cron_user" -
}

if [ -z "$(command -v crontab)" ]; then

  echo "|" && read -p "|   SyAgent needs cron. Do you want to install it? [Y/n] " input_variable_install

  if answer_yes "$input_variable_install"; then
    if [ -n "$(command -v apt-get)" ]; then
      apt-get -y update
      apt-get -y install cron
    elif [ -n "$(command -v pacman)" ]; then
      pacman -S --noconfirm cronie
    elif [ -n "$(command -v yum)" ]; then
      yum -y install cronie

      if [ -z "$(command -v crontab)" ]; then
        yum -y install vixie-cron
      fi
    else
      fail "|\n|   Error: Cannot find a supported package manager to install CronTab\n|"
    fi
  fi

  if [ -z "$(command -v crontab)" ]; then
    fail "|\n|   Error: Cannot install CronTab, please install the CronTab and run the script again\n|"
  fi
fi

if ! ps -Al | grep -q "[c]ron"; then

  echo "|" && read -p "|   Cron is is down. Do you want to start it? [Y/n] " input_variable_service

  if answer_yes "$input_variable_service"; then
    if [ -n "$(command -v apt-get)" ]; then
      service cron start
    elif [ -n "$(command -v yum)" ]; then
      chkconfig crond on
      service crond start
    elif [ -n "$(command -v pacman)" ]; then
      systemctl start cronie
      systemctl enable cronie
    fi
  fi

  if ! ps -Al | grep -q "[c]ron"; then
    fail "|\n|   Error: Error when trying to start the Cron\n|"
  fi
fi

if id -u syAgent >/dev/null 2>&1; then
  remove_agent_cron syAgent
else
  remove_agent_cron root
fi

if [ -f /etc/syAgent/sh-agent.sh ]; then
  rm -Rf /etc/syAgent

  if id -u syAgent >/dev/null 2>&1; then
    userdel syAgent
  fi
fi

mkdir -p /etc/syAgent

printBold "|   Downloading sh-agent.sh to /etc/syAgent\n|\n|   + $(wget -nv -o /dev/stdout -O /etc/syAgent/sh-agent.sh --no-check-certificate https://raw.githubusercontent.com/syagent/agent-2/main/sh-agent.sh)"

if [ -f /etc/syAgent/sh-agent.sh ]; then
  echo "$1" >/etc/syAgent/sa-auth.log

  if ! id -u syAgent >/dev/null 2>&1; then
    useradd syAgent -r -d /etc/syAgent -s /bin/false
  fi

  chown -R syAgent:syAgent /etc/syAgent && chmod -R 700 /etc/syAgent

  crontab -u syAgent -l 2>/dev/null | grep -v "/etc/syAgent/sh-agent.sh" | {
    cat
    echo "*/1 * * * * bash /etc/syAgent/sh-agent.sh > /etc/syAgent/sh-cron.log 2>&1"
  } | crontab -u syAgent -

  printBold "| ================================================\n"
	printGreen "| Success: The syAgent agent installed\n"
	printBold "| ================================================\n"

  if [ -f "$0" ]; then
    rm -f "$0"
  fi
else
  fail "\tError: The syAgent agent is not installed\n"
fi

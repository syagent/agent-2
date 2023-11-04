#!/bin/bash
# @version		1.0.7

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

version="1.0.7"

if [ -f /etc/syAgent/sa-auth.log ]; then
  token_file=($(cat /etc/syAgent/sa-auth.log))
else
  echo "Error: Auth file required"
  exit 1
fi

function sed_rt() {
  echo "$1" | sed -e 's/^ *//g' -e 's/ *$//g' | sed -n '1 p'
}

function to_base64() {
  echo "$1" | tr -d '\n' | base64 | tr -d '=' | tr -d '\n' | sed 's/\//%2F/g' | sed 's/\+/%2B/g'
}

function to_int() {
  echo ${1/\.*/}
}

function to_num() {
  case $1 in
  '' | *[!0-9\.]*) echo 0 ;;
  *) echo $1 ;;
  esac
}

version=$(sed_rt "$version")

uptime=$(sed_rt $(to_int "$(cat /proc/uptime | awk '{ print $1 }')"))

sessions=$(sed_rt "$(who | wc -l)")

processes=$(sed_rt "$(ps axc | wc -l)")

processes_list="$(ps axc -o uname:12,pcpu,rss,cmd --sort=-pcpu,-rss --noheaders --width 120)"
processes_list="$(echo "$processes_list" | grep -v " ps$" | sed 's/ \+ / /g' | sed '/^$/d' | tr "\n" ";")"

file_handles=$(sed_rt $(to_num "$(cat /proc/sys/fs/file-nr | awk '{ print $1 }')"))
file_handles_limit=$(sed_rt $(to_num "$(cat /proc/sys/fs/file-nr | awk '{ print $3 }')"))

os_kernel=$(sed_rt "$(uname -r)")

if ls /etc/*release >/dev/null 2>&1; then
  os_name=$(sed_rt "$(cat /etc/*release | grep '^PRETTY_NAME=\|^NAME=\|^DISTRIB_ID=' | awk -F\= '{ print $2 }' | tr -d '"' | tac)")
fi

if [ -z "$os_name" ]; then
  if [ -e /etc/redhat-release ]; then
    os_name=$(sed_rt "$(cat /etc/redhat-release)")
  elif [ -e /etc/debian_version ]; then
    os_name=$(sed_rt "Debian $(cat /etc/debian_version)")
  fi

  if [ -z "$os_name" ]; then
    os_name=$(sed_rt "$(uname -s)")
  fi
fi

case $(uname -m) in
x86_64)
  os_arch=$(sed_rt "x64")
  ;;
i*86)
  os_arch=$(sed_rt "x86")
  ;;
*)
  os_arch=$(sed_rt "$(uname -m)")
  ;;
esac

cpu_name=$(sed_rt "$(cat /proc/cpuinfo | grep 'model name' | awk -F\: '{ print $2 }')")
cpu_cores=$(sed_rt "$(($(cat /proc/cpuinfo | grep 'model name' | awk -F\: '{ print $2 }' | sed -e :a -e '$!N;s/\n/\|/;ta' | tr -cd \| | wc -c) + 1))")

if [ -z "$cpu_name" ]; then
  cpu_name=$(sed_rt "$(lscpu | grep "Model name" | awk -F\: '{ print $2 }')")
  cpu_cores=$(sed_rt "$(lscpu | grep "Core(s) per cluster" | awk -F\: '{ print $2 }')")
fi

if [ -z "$cpu_name" ]; then
  cpu_name=$(sed_rt "$(cat /proc/cpuinfo | grep 'vendor_id' | awk -F\: '{ print $2 } END { if (!NR) print "N/A" }')")
  cpu_cores=$(sed_rt "$(($(cat /proc/cpuinfo | grep 'vendor_id' | awk -F\: '{ print $2 }' | sed -e :a -e '$!N;s/\n/\|/;ta' | tr -cd \| | wc -c) + 1))")
fi

cpu_freq=$(sed_rt "$(cat /proc/cpuinfo | grep 'cpu MHz' | awk -F\: '{ print $2 }')")

if [ -z "$cpu_freq" ]; then
  cpu_freq=$(sed_rt $(to_num "$(lscpu | grep 'CPU MHz' | awk -F\: '{ print $2 }' | sed -e 's/^ *//g' -e 's/ *$//g')"))
fi

ram_total=$(sed_rt $(to_num "$(cat /proc/meminfo | grep ^MemTotal: | awk '{ print $2 }')"))
ram_free=$(sed_rt $(to_num "$(cat /proc/meminfo | grep ^MemFree: | awk '{ print $2 }')"))
ram_cached=$(sed_rt $(to_num "$(cat /proc/meminfo | grep ^Cached: | awk '{ print $2 }')"))
ram_buffers=$(sed_rt $(to_num "$(cat /proc/meminfo | grep ^Buffers: | awk '{ print $2 }')"))
ram_usage=$((($ram_total - ($ram_free + $ram_cached + $ram_buffers)) * 1024))
ram_total=$(($ram_total * 1024))

swap_total=$(sed_rt $(to_num "$(cat /proc/meminfo | grep ^SwapTotal: | awk '{ print $2 }')"))
swap_free=$(sed_rt $(to_num "$(cat /proc/meminfo | grep ^SwapFree: | awk '{ print $2 }')"))
swap_usage=$((($swap_total - $swap_free) * 1024))
swap_total=$(($swap_total * 1024))

disk_total=$(sed_rt $(to_num "$(($(df -P -B 1 | grep '^/' | awk '{ print $2 }' | sed -e :a -e '$!N;s/\n/+/;ta')))"))
disk_usage=$(sed_rt $(to_num "$(($(df -P -B 1 | grep '^/' | awk '{ print $3 }' | sed -e :a -e '$!N;s/\n/+/;ta')))"))

disk_array=$(sed_rt "$(df -P -B 1 | grep '^/' | awk '{ print $1" "$2" "$3";" }' | sed -e :a -e '$!N;s/\n/ /;ta' | awk '{ print $0 } END { if (!NR) print "N/A" }')")


#docker stats
if command -v docker &> /dev/null; then
    docker_stats=$(docker stats --no-stream --format "container_name:{{.Name}},container_cpu:{{.CPUPerc}},container_mem:{{.MemUsage}},container_net_io:{{.NetIO}}" | tail -n +2 | tr '\n' ' ')
else
    docker_stats=""
fi

# apps
get_version() {
    program=$1
    version=$($program 2>&1)
    if [ $? -eq 0 ]; then
        echo "$version" | awk '{print $3}'
    else
        echo "N/A"
    fi
}

get_db_version() {
    db_command=$1
    version=$($db_command --version 2>&1)
    if [ $? -eq 0 ]; then
        echo "$version" | head -n 1 | awk '{print $3}'
    else
        echo "N/A"
    fi
}

get_language_version() {
    language=$1
    version=$($language --version 2>&1)
    if [ $? -eq 0 ]; then
        echo "$version" | head -n 1 | awk '{print $3}'
    else
        echo "N/A"
    fi
}

get_nodejs_version() {
    version=$(node --version 2>&1)
    if [ $? -eq 0 ]; then
        echo "$version"
    else
        echo "N/A"
    fi
}

# Check and collect version information safely
nginx_version=$(get_version "nginx -v")
apache_version=$(get_version "httpd -v")
mysql_version=$(get_version "mysql --version")
php_version=$(get_version "php -v")
docker_version=$(get_version "docker -v")
python_version=$(get_language_version "python")
perl_version=$(get_language_version "perl")
ruby_version=$(get_language_version "ruby")
java_version=$(get_language_version "java")
gcc_version=$(get_language_version "gcc")
gpp_version=$(get_language_version "g++")
postgres_version=$(get_db_version "psql")
mongo_version=$(get_db_version "mongo --version | head -n 1")
redis_version=$(get_version "redis-server")
kafka_version=$(get_version "kafka-server")
rabbitmq_version=$(get_version "rabbitmq")
nodejs_version=$(get_nodejs_version)


success_attempts=""
failed_attempts=""
# Check if log files exist
if [ -f /var/log/auth.log ] || [ -f /var/log/secure ]; then
    # Count all SSH connection attempts
    success_attempts=$(grep 'Accepted password for\|Accepted publickey for' /var/log/auth.log /var/log/secure | wc -l)
    # Count failed SSH connection attempts
    failed_attempts=$(grep 'Failed password for\|Failed publickey for' /var/log/auth.log /var/log/secure | wc -l)
else
    echo "Log files not found. Skipping SSH attempts analysis."
fi



if [ -n "$(command -v ss)" ]; then
  connections=$(sed_rt $(to_num "$(ss -tun | tail -n +2 | wc -l)"))
else
  connections=$(sed_rt $(to_num "$(netstat -tun | tail -n +3 | wc -l)"))
fi

nic=$(sed_rt "$(ip route get 8.8.8.8 | grep dev | awk -F'dev' '{ print $2 }' | awk '{ print $1 }')")

if [ -z $nic ]; then
  nic=$(sed_rt "$(ip link show | grep 'eth[0-9]' | awk '{ print $2 }' | tr -d ':')")
fi

ipv4=$(sed_rt "$(ip addr show $nic | grep 'inet ' | awk '{ print $2 }' | awk -F\/ '{ print $1 }' | grep -v '^127' | awk '{ print $0 } END { if (!NR) print "N/A" }')")
ipv6=$(sed_rt "$(ip addr show $nic | grep 'inet6 ' | awk '{ print $2 }' | awk -F\/ '{ print $1 }' | grep -v '^::' | grep -v '^0000:' | grep -v '^fe80:' | awk '{ print $0 } END { if (!NR) print "N/A" }')")

if [ -d /sys/class/net/$nic/statistics ]; then
  rx=$(sed_rt $(to_num "$(cat /sys/class/net/$nic/statistics/rx_bytes)"))
  tx=$(sed_rt $(to_num "$(cat /sys/class/net/$nic/statistics/tx_bytes)"))
else
  rx=$(sed_rt $(to_num "$(ip -s link show $nic | grep '[0-9]*' | grep -v '[A-Za-z]' | awk '{ print $1 }' | sed -n '1 p')"))
  tx=$(sed_rt $(to_num "$(ip -s link show $nic | grep '[0-9]*' | grep -v '[A-Za-z]' | awk '{ print $1 }' | sed -n '2 p')"))
fi

load=$(sed_rt "$(cat /proc/loadavg | awk '{ print $1" "$2" "$3 }')")

time=$(date +%s)
stat=($(cat /proc/stat | head -n1 | sed 's/[^0-9 ]*//g' | sed 's/^ *//'))
cpu=$((${stat[0]} + ${stat[1]} + ${stat[2]} + ${stat[3]}))
io=$((${stat[3]} + ${stat[4]}))
idle=${stat[3]}

if [ -e /etc/syAgent/pe-data.log ]; then
  data=($(cat /etc/syAgent/pe-data.log))
  interval=$(($time - ${data[0]}))
  cpu_gap=$(($cpu - ${data[1]}))
  io_gap=$(($io - ${data[2]}))
  idle_gap=$(($idle - ${data[3]}))

  if [[ $cpu_gap > "0" ]]; then
    load_cpu=$(((1000 * ($cpu_gap - $idle_gap) / $cpu_gap + 5) / 10))
  fi

  if [[ $io_gap > "0" ]]; then
    load_io=$(((1000 * ($io_gap - $idle_gap) / $io_gap + 5) / 10))
  fi

  if [[ $rx > ${data[4]} ]]; then
    rx_gap=$(($rx - ${data[4]}))
  fi

  if [[ $tx > ${data[5]} ]]; then
    tx_gap=$(($tx - ${data[5]}))
  fi
fi

echo "$time $cpu $io $idle $rx $tx" >/etc/syAgent/pe-data.log

rx_gap=$(sed_rt $(to_num "$rx_gap"))
tx_gap=$(sed_rt $(to_num "$tx_gap"))
load_cpu=$(sed_rt $(to_num "$load_cpu"))
load_io=$(sed_rt $(to_num "$load_io"))

multipart_data="token=${token_file[0]}&data=$(to_base64 "$version") $(to_base64 "$uptime") $(to_base64 "$sessions") $(to_base64 "$processes") $(to_base64 "$processes_list") $(to_base64 "$file_handles") $(to_base64 "$file_handles_limit") $(to_base64 "$os_kernel") $(to_base64 "$os_name") $(to_base64 "$os_arch") $(to_base64 "$cpu_name") $(to_base64 "$cpu_cores") $(to_base64 "$cpu_freq") $(to_base64 "$ram_total") $(to_base64 "$ram_usage") $(to_base64 "$swap_total") $(to_base64 "$swap_usage") $(to_base64 "$disk_array") $(to_base64 "$disk_total") $(to_base64 "$disk_usage") $(to_base64 "$connections") $(to_base64 "$nic") $(to_base64 "$ipv4") $(to_base64 "$ipv6") $(to_base64 "$rx") $(to_base64 "$tx") $(to_base64 "$rx_gap") $(to_base64 "$tx_gap") $(to_base64 "$load") $(to_base64 "$load_cpu") $(to_base64 "$load_io") $(to_base64 "$docker_stats") $(to_base64 "nginx_version:$nginx_version,apache_version:$apache_version,mysql_version:$mysql_version,postgres_version:$postgres_version,mongo_version:$mongo_version,php_version:$php_version,docker_version:$docker_version,python_version:$python_version,perl_version:$perl_version,ruby_version:$ruby_version,java_version:$java_version,gcc_version:$gcc_version,gpp_version:$gpp_version,redis_version:$redis_version,kafka_version:$kafka_version,rabbitmq_version:$rabbitmq_version") $(to_base64 "success_attempts:$success_attempts,failed_attempts:$failed_attempts")"

if [ -n "$(command -v timeout)" ]; then
  timeout -s SIGKILL 30 wget -q -o /dev/null -O /etc/syAgent/sh-agent.log -T 25 --post-data "$multipart_data" --no-check-certificate "https://agent.syagent.com/agent"
else
  wget -q -o /dev/null -O /etc/syAgent/sh-agent.log -T 25 --post-data "$multipart_data" --no-check-certificate "https://agent.syagent.com/agent"
  wget_process_id=$!
  wget_counter=0
  wget_timeout=30

  while kill -0 "$wget_process_id" && ((wget_counter < wget_timeout)); do
    sleep 1
    ((wget_counter++))
  done

  kill -0 "$wget_process_id" && kill -s SIGKILL "$wget_process_id"
fi

exit 0

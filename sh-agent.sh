#!/bin/bash
# @version 1.1.2 - JSON payload version with defaults for missing values

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH=/usr/local/bin:/usr/bin:/bin
export DOCKER_HOST=unix:///var/run/docker.sock

if [ -f /etc/syAgent/sa-auth.log ]; then
  token_file=($(cat /etc/syAgent/sa-auth.log))
else
  echo "Error: Auth file required"
  exit 1
fi

function sed_rt() {
  echo "$1" | sed -e 's/^ *//g' -e 's/ *$//g' | sed -n '1 p'
}

function to_num() {
  case $1 in
  '' | *[!0-9\.]* ) echo 0 ;;
  *) echo $1 ;;
  esac
}

uptime=$(sed_rt $(cut -d. -f1 /proc/uptime))
sessions=$(who | wc -l)
processes=$(ps axc | wc -l)
processes_list=$(ps axc -o uname:12,pcpu,rss,cmd --sort=-pcpu,-rss --noheaders --width 120 | grep -v " ps$" | sed '/^$/d' | tr "\n" ";")

file_handles=$(cut -f1 /proc/sys/fs/file-nr)
file_handles_limit=$(cut -f3 /proc/sys/fs/file-nr)
os_kernel=$(uname -r)

if ls /etc/*release >/dev/null 2>&1; then
  os_name=$(grep '^PRETTY_NAME=' /etc/*release | cut -d= -f2 | tr -d '"')
fi

case $(uname -m) in
  x86_64) os_arch="x64";;
  i*86) os_arch="x86";;
  *) os_arch=$(uname -m);;
esac

cpu_name=$(grep 'model name' /proc/cpuinfo | head -n1 | cut -d: -f2 | sed_rt)
cpu_cores=$(grep -c '^processor' /proc/cpuinfo)
cpu_freq=$(grep 'cpu MHz' /proc/cpuinfo | head -n1 | cut -d: -f2 | sed_rt)

ram_total=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') * 1024))
ram_free=$(($(grep MemFree /proc/meminfo | awk '{print $2}') * 1024))
ram_cached=$(($(grep ^Cached: /proc/meminfo | awk '{print $2}') * 1024))
ram_buffers=$(($(grep ^Buffers: /proc/meminfo | awk '{print $2}') * 1024))
ram_usage=$((ram_total - (ram_free + ram_cached + ram_buffers)))

swap_total=$(($(grep SwapTotal /proc/meminfo | awk '{print $2}') * 1024))
swap_free=$(($(grep SwapFree /proc/meminfo | awk '{print $2}') * 1024))
swap_usage=$((swap_total - swap_free))

disk_total=$(df -P -B1 | awk '$1 ~ /^\// {sum += $2} END {print sum}')
disk_usage=$(df -P -B1 | awk '$1 ~ /^\// {sum += $3} END {print sum}')
disk_array=$(df -P -B1 | awk '$1 ~ /^\// {print $1" "$2" "$3";"}' | tr '\n' ' ')

get_version() {
  version=$($1 2>&1)
  [ $? -eq 0 ] && echo "$version" | awk '{print $3}' || echo ""
}

get_db_version() {
  version=$($1 --version 2>&1)
  [ $? -eq 0 ] && echo "$version" | head -n 1 | awk '{print $3}' || echo ""
}

get_language_version() {
  version=$($1 --version 2>&1)
  [ $? -eq 0 ] && echo "$version" | head -n 1 | awk '{print $3}' || echo ""
}

get_nodejs_version() {
  version=$(node --version 2>&1)
  [ $? -eq 0 ] && echo "$version" || echo ""
}

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
mongo_version=$(get_db_version "mongo")
redis_version=$(get_version "redis-server")
kafka_version=$(get_version "kafka-server")
rabbitmq_version=$(get_version "rabbitmq")
nodejs_version=$(get_nodejs_version)

success_attempts=$(grep -hc 'Accepted' /var/log/auth.log /var/log/secure 2>/dev/null || echo 0)
failed_attempts=$(grep -hc 'Failed password' /var/log/auth.log /var/log/secure 2>/dev/null || echo 0)

nic=$(ip route get 8.8.8.8 | awk '/dev/ {print $5}')
ipv4=$(ip -4 addr show $nic | awk '/inet / {print $2}' | cut -d/ -f1 | grep -v '^127' | head -n1)
ipv6=$(ip -6 addr show $nic | awk '/inet6 / && !/fe80/ {print $2}' | cut -d/ -f1 | head -n1)

rx=$(cat /sys/class/net/$nic/statistics/rx_bytes)
tx=$(cat /sys/class/net/$nic/statistics/tx_bytes)

load=$(cut -d' ' -f1-3 /proc/loadavg)

# GPU Stats
gpu_info=""
gpu_procs_info=""
if command -v nvidia-smi &> /dev/null; then
  gpu_info=$(nvidia-smi --query-gpu=index,name,utilization.gpu,utilization.memory,memory.total,memory.used,temperature.gpu --format=csv,noheader,nounits | jq -Rs .)
  gpu_procs_info=$(nvidia-smi --query-compute-apps=gpu_uuid,pid,process_name,used_memory --format=csv,noheader,nounits | while IFS= read -r line; do
    pid=$(echo $line | cut -d, -f2 | sed_rt)
    user=$(ps -o user= -p "$pid" 2>/dev/null | sed_rt)
    echo "$line,user:$user"
  done | jq -Rs .)
else
  gpu_info="\"\""
  gpu_procs_info="\"\""
fi

cpu_freq=${cpu_freq:-0}
cpu_cores=${cpu_cores:-0}
escaped_processes_list=$(echo "${processes_list:-}" | jq -Rs .)
escaped_disk_array=$(echo "${disk_array:-}" | jq -Rs .)

json_payload=$(cat <<EOF
{
  "token": "${token_file[0]}",
  "version": "1.1.2",
  "uptime": ${uptime:-0},
  "sessions": ${sessions:-0},
  "processes": ${processes:-0},
  "processes_list": $escaped_processes_list,
  "file_handles": ${file_handles:-0},
  "file_handles_limit": ${file_handles_limit:-0},
  "os_kernel": "${os_kernel:-}",
  "os_name": "${os_name:-}",
  "os_arch": "${os_arch:-}",
  "cpu_name": "${cpu_name:-}",
  "cpu_cores": ${cpu_cores},
  "cpu_freq": ${cpu_freq},
  "ram_total": ${ram_total:-0},
  "ram_usage": ${ram_usage:-0},
  "swap_total": ${swap_total:-0},
  "swap_usage": ${swap_usage:-0},
  "disk_array": $escaped_disk_array,
  "disk_total": ${disk_total:-0},
  "disk_usage": ${disk_usage:-0},
  "connections": 0,
  "nic": "${nic:-}",
  "ipv4": "${ipv4:-}",
  "ipv6": "${ipv6:-}",
  "rx": ${rx:-0},
  "tx": ${tx:-0},
  "load": "${load:-}",
  "load_cpu": 0,
  "load_io": 0,
  "versions": {
    "nginx": "${nginx_version:-}",
    "apache": "${apache_version:-}",
    "mysql": "${mysql_version:-}",
    "postgres": "${postgres_version:-}",
    "mongo": "${mongo_version:-}",
    "php": "${php_version:-}",
    "docker": "${docker_version:-}",
    "python": "${python_version:-}",
    "perl": "${perl_version:-}",
    "ruby": "${ruby_version:-}",
    "java": "${java_version:-}",
    "gcc": "${gcc_version:-}",
    "gpp": "${gpp_version:-}",
    "redis": "${redis_version:-}",
    "kafka": "${kafka_version:-}",
    "rabbitmq": "${rabbitmq_version:-}",
    "nodejs": "${nodejs_version:-}"
  },
  "ssh_attempts": {
    "success": ${success_attempts:-0},
    "failed": ${failed_attempts:-0}
  },
  "gpu_info": $gpu_info,
  "gpu_procs_info": $gpu_procs_info
}
EOF
)

# Validate JSON before sending
if echo "$json_payload" | jq . > /dev/null 2>&1; then
  curl -s -X POST "https://free-decent-boar.ngrok-free.app/agent" \
    -H "Content-Type: application/json" \
    --data-binary "$json_payload" \
    -o /etc/syAgent/sh-agent.log
else
  echo "Invalid JSON payload. Skipping send."
  exit 1
fi

exit 0

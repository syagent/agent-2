#!/bin/bash
# @version		1.1.0

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DOCKER_HOST=unix:///var/run/docker.sock

version="1.1.0"
dry_run=false

if [ "$1" = "--dry-run" ] || [ "$1" = "--debug" ]; then
  dry_run=true
fi

if [ -f /etc/syAgent/sa-auth.log ]; then
  read -r token < /etc/syAgent/sa-auth.log
else
  echo "Error: Auth file required"
  exit 1
fi

if [ -z "$token" ]; then
  echo "Error: Auth token is empty"
  exit 1
fi

function sed_rt() {
  printf "%s\n" "$1" | sed -e 's/^ *//g' -e 's/ *$//g' | sed -n '1 p'
}

function to_base64() {
  printf "%s" "$1" | base64 | tr -d '=' | tr -d '\n' | sed 's/\//%2F/g' | sed 's/\+/%2B/g'
}

function to_int() {
  echo "${1/\.*/}"
}

function to_num() {
  case "$1" in
  '' | *[!0-9\.]*) echo 0 ;;
  *) echo "$1" ;;
  esac
}

function require_commands() {
  local missing_commands=""

  for required_command in "$@"; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
      missing_commands="$missing_commands $required_command"
    fi
  done

  if [ -n "$missing_commands" ]; then
    echo "Error: Missing required commands:$missing_commands"
    exit 1
  fi
}

require_commands awk base64 cat date df grep head ps sed tail tr uname wc wget who

version=$(sed_rt "$version")

uptime=$(sed_rt "$(to_int "$(cat /proc/uptime | awk '{ print $1 }')")")

sessions=$(sed_rt "$(who | wc -l)")

processes=$(sed_rt "$(ps axc | wc -l)")

processes_list="$(ps axc -o uname:12,pcpu,rss,cmd --sort=-pcpu,-rss --noheaders --width 120)"
processes_list="$(echo "$processes_list" | grep -v " ps$" | sed 's/ \+ / /g' | sed '/^$/d' | tr "\n" ";")"

file_handles=$(sed_rt "$(to_num "$(cat /proc/sys/fs/file-nr | awk '{ print $1 }')")")
file_handles_limit=$(sed_rt "$(to_num "$(cat /proc/sys/fs/file-nr | awk '{ print $3 }')")")

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
  cpu_freq=$(sed_rt "$(to_num "$(lscpu | grep 'CPU MHz' | awk -F\: '{ print $2 }' | sed -e 's/^ *//g' -e 's/ *$//g')")")
fi

ram_total=$(sed_rt "$(to_num "$(cat /proc/meminfo | grep ^MemTotal: | awk '{ print $2 }')")")
ram_available=$(sed_rt "$(to_num "$(cat /proc/meminfo | grep ^MemAvailable: | awk '{ print $2 }')")")

if [ "$ram_available" = "0" ]; then
  ram_free=$(sed_rt "$(to_num "$(cat /proc/meminfo | grep ^MemFree: | awk '{ print $2 }')")")
  ram_cached=$(sed_rt "$(to_num "$(cat /proc/meminfo | grep ^Cached: | awk '{ print $2 }')")")
  ram_buffers=$(sed_rt "$(to_num "$(cat /proc/meminfo | grep ^Buffers: | awk '{ print $2 }')")")
  ram_available=$((ram_free + ram_cached + ram_buffers))
fi

ram_usage=$(((ram_total - ram_available) * 1024))
ram_total=$((ram_total * 1024))

swap_total=$(sed_rt "$(to_num "$(cat /proc/meminfo | grep ^SwapTotal: | awk '{ print $2 }')")")
swap_free=$(sed_rt "$(to_num "$(cat /proc/meminfo | grep ^SwapFree: | awk '{ print $2 }')")")
swap_usage=$(((swap_total - swap_free) * 1024))
swap_total=$((swap_total * 1024))

disk_total=$(sed_rt "$(to_num "$(($(df -P -B 1 | grep '^/' | awk '{ print $2 }' | sed -e :a -e '$!N;s/\n/+/;ta')))")")
disk_usage=$(sed_rt "$(to_num "$(($(df -P -B 1 | grep '^/' | awk '{ print $3 }' | sed -e :a -e '$!N;s/\n/+/;ta')))")")

disk_array=$(sed_rt "$(df -P -B 1 | grep '^/' | awk '{ print $1" "$2" "$3";" }' | sed -e :a -e '$!N;s/\n/ /;ta' | awk '{ print $0 } END { if (!NR) print "N/A" }')")




get_command_version() {
  local field="$1"
  shift
  local output

  if ! command -v "$1" >/dev/null 2>&1; then
    echo "N/A"
    return
  fi

  output="$("$@" 2>&1)"
  if [ $? -eq 0 ]; then
    echo "$output" | head -n 1 | awk -v field="$field" '{ print $field }'
  else
    echo "N/A"
  fi
}

nginx_version=$(get_command_version 3 nginx -v)
apache_version=$(get_command_version 3 httpd -v)
mysql_version=$(get_command_version 3 mysql --version)
php_version=$(get_command_version 2 php -v)
docker_version=$(get_command_version 3 docker -v)
python_version=$(get_command_version 2 python --version)
perl_version=$(get_command_version 4 perl --version)
ruby_version=$(get_command_version 2 ruby --version)
java_version=$(get_command_version 3 java --version)
gcc_version=$(get_command_version 3 gcc --version)
gpp_version=$(get_command_version 3 g++ --version)
postgres_version=$(get_command_version 3 psql --version)
mongo_version=$(get_command_version 3 mongo --version)
redis_version=$(get_command_version 3 redis-server --version)
kafka_version=$(get_command_version 3 kafka-server --version)
rabbitmq_version=$(get_command_version 2 rabbitmq --version)
nodejs_version=$(get_command_version 1 node --version)


success_attempts=""
failed_attempts=""
auth_logs=""

for auth_log in /var/log/auth.log /var/log/secure; do
  if [ -r "$auth_log" ]; then
    auth_logs="$auth_logs $auth_log"
  fi
done

if [ -n "$auth_logs" ]; then
  success_attempts=$(grep 'Accepted password for\|Accepted publickey for' $auth_logs 2>/dev/null | wc -l)
  failed_attempts=$(grep 'Failed password for\|Failed publickey for' $auth_logs 2>/dev/null | wc -l)
else
  success_attempts=0
  failed_attempts=0
fi



if [ -n "$(command -v ss)" ]; then
  connections=$(sed_rt "$(to_num "$(ss -tun | tail -n +2 | wc -l)")")
elif [ -n "$(command -v netstat)" ]; then
  connections=$(sed_rt "$(to_num "$(netstat -tun | tail -n +3 | wc -l)")")
else
  connections=0
fi

nic=""

if [ -n "$(command -v ip)" ]; then
  nic=$(sed_rt "$(ip route get 8.8.8.8 2>/dev/null | grep dev | awk -F'dev' '{ print $2 }' | awk '{ print $1 }')")

  if [ -z "$nic" ]; then
    nic=$(sed_rt "$(ip -o link show up | awk -F': ' '$2 != "lo" { print $2; exit }')")
  fi
fi

if [ -n "$nic" ]; then
  ipv4=$(sed_rt "$(ip addr show "$nic" | grep 'inet ' | awk '{ print $2 }' | awk -F\/ '{ print $1 }' | grep -v '^127' | awk '{ print $0 } END { if (!NR) print "N/A" }')")
  ipv6=$(sed_rt "$(ip addr show "$nic" | grep 'inet6 ' | awk '{ print $2 }' | awk -F\/ '{ print $1 }' | grep -v '^::' | grep -v '^0000:' | grep -v '^fe80:' | awk '{ print $0 } END { if (!NR) print "N/A" }')")
else
  nic="N/A"
  ipv4="N/A"
  ipv6="N/A"
fi

if [ -d "/sys/class/net/$nic/statistics" ]; then
  rx=$(sed_rt "$(to_num "$(cat "/sys/class/net/$nic/statistics/rx_bytes")")")
  tx=$(sed_rt "$(to_num "$(cat "/sys/class/net/$nic/statistics/tx_bytes")")")
elif [ "$nic" != "N/A" ]; then
  rx=$(sed_rt "$(to_num "$(ip -s link show "$nic" | grep '[0-9]*' | grep -v '[A-Za-z]' | awk '{ print $1 }' | sed -n '1 p')")")
  tx=$(sed_rt "$(to_num "$(ip -s link show "$nic" | grep '[0-9]*' | grep -v '[A-Za-z]' | awk '{ print $1 }' | sed -n '2 p')")")
else
  rx=0
  tx=0
fi

load=$(sed_rt "$(cat /proc/loadavg | awk '{ print $1" "$2" "$3 }')")

time=$(date +%s)
stat=($(cat /proc/stat | head -n1 | sed 's/[^0-9 ]*//g' | sed 's/^ *//'))
cpu=$((${stat[0]} + ${stat[1]} + ${stat[2]} + ${stat[3]}))
io=$((${stat[3]} + ${stat[4]}))
idle=${stat[3]}

if [ -e /etc/syAgent/pe-data.log ]; then
  data=($(cat /etc/syAgent/pe-data.log))
  previous_time=$(to_num "${data[0]}")
  previous_cpu=$(to_num "${data[1]}")
  previous_io=$(to_num "${data[2]}")
  previous_idle=$(to_num "${data[3]}")
  previous_rx=$(to_num "${data[4]}")
  previous_tx=$(to_num "${data[5]}")

  interval=$((time - previous_time))
  cpu_gap=$((cpu - previous_cpu))
  io_gap=$((io - previous_io))
  idle_gap=$((idle - previous_idle))

  if [ "$cpu_gap" -gt 0 ]; then
    load_cpu=$(((1000 * ($cpu_gap - $idle_gap) / $cpu_gap + 5) / 10))
  fi

  if [ "$io_gap" -gt 0 ]; then
    load_io=$(((1000 * ($io_gap - $idle_gap) / $io_gap + 5) / 10))
  fi

  if [ "$rx" -gt "$previous_rx" ]; then
    rx_gap=$((rx - previous_rx))
  fi

  if [ "$tx" -gt "$previous_tx" ]; then
    tx_gap=$((tx - previous_tx))
  fi
fi

echo "$time $cpu $io $idle $rx $tx" >/etc/syAgent/pe-data.log

rx_gap=$(sed_rt "$(to_num "$rx_gap")")
tx_gap=$(sed_rt "$(to_num "$tx_gap")")
load_cpu=$(sed_rt "$(to_num "$load_cpu")")
load_io=$(sed_rt "$(to_num "$load_io")")

gpu_info=""

if command -v nvidia-smi &> /dev/null; then
  raw_gpu_info=$(nvidia-smi --query-gpu=index,name,utilization.gpu,utilization.memory,memory.total,memory.used,temperature.gpu --format=csv,noheader,nounits)

  while IFS=',' read -r gpu_index gpu_name gpu_util mem_util mem_total mem_used temp; do
    gpu_info+="gpu_index:$(sed_rt "$gpu_index"),gpu_name:$(sed_rt "$gpu_name"),gpu_util:$(sed_rt "$gpu_util"),mem_util:$(sed_rt "$mem_util"),mem_total:$(sed_rt "$mem_total"),mem_used:$(sed_rt "$mem_used"),temp:$(sed_rt "$temp");"
  done <<< "$raw_gpu_info"
else
  gpu_info="nvidia-smi not available"
fi

gpu_procs_info=""

if command -v nvidia-smi &> /dev/null; then
  raw_proc_info=$(nvidia-smi --query-compute-apps=gpu_uuid,pid,process_name,used_memory --format=csv,noheader,nounits)

	  if [ -n "$raw_proc_info" ]; then
	    while IFS=',' read -r gpu_uuid pid pname used_mem; do
	      user=$(sed_rt "$(ps -o user= -p "$(sed_rt "$pid")" 2>/dev/null)")
	      gpu_procs_info+="gpu_uuid:$(sed_rt "$gpu_uuid"),pid:$(sed_rt "$pid"),user:$user,process:$(sed_rt "$pname"),used_mem:$(sed_rt "$used_mem");"
	    done <<< "$raw_proc_info"
  else
    gpu_procs_info="no active GPU processes"
  fi
else
  gpu_procs_info="nvidia-smi not available"
fi

multipart_data="token=$token&data=$(to_base64 "$version") $(to_base64 "$uptime") $(to_base64 "$sessions") $(to_base64 "$processes") $(to_base64 "$processes_list") $(to_base64 "$file_handles") $(to_base64 "$file_handles_limit") $(to_base64 "$os_kernel") $(to_base64 "$os_name") $(to_base64 "$os_arch") $(to_base64 "$cpu_name") $(to_base64 "$cpu_cores") $(to_base64 "$cpu_freq") $(to_base64 "$ram_total") $(to_base64 "$ram_usage") $(to_base64 "$swap_total") $(to_base64 "$swap_usage") $(to_base64 "$disk_array") $(to_base64 "$disk_total") $(to_base64 "$disk_usage") $(to_base64 "$connections") $(to_base64 "$nic") $(to_base64 "$ipv4") $(to_base64 "$ipv6") $(to_base64 "$rx") $(to_base64 "$tx") $(to_base64 "$rx_gap") $(to_base64 "$tx_gap") $(to_base64 "$load") $(to_base64 "$load_cpu") $(to_base64 "$load_io") $(to_base64 "nginx_version:$nginx_version,apache_version:$apache_version,mysql_version:$mysql_version,postgres_version:$postgres_version,mongo_version:$mongo_version,php_version:$php_version,docker_version:$docker_version,python_version:$python_version,perl_version:$perl_version,ruby_version:$ruby_version,java_version:$java_version,gcc_version:$gcc_version,gpp_version:$gpp_version,redis_version:$redis_version,kafka_version:$kafka_version,rabbitmq_version:$rabbitmq_version,nodejs_version:$nodejs_version") $(to_base64 "success_attempts:$success_attempts,failed_attempts:$failed_attempts") $(to_base64 "$gpu_info") $(to_base64 "$gpu_procs_info")"

if [ "$dry_run" = true ]; thenc
  printf "%s\n" "$multipart_data"
  exit 0
fi

if [ -n "$(command -v timeout)" ]; then
  timeout -s SIGKILL 30 wget -q -o /dev/null -O /etc/syAgent/sh-agent.log -T 25 --post-data "$multipart_data" --no-check-certificate "https://agent.syagent.com/agent"
else
  wget -q -o /dev/null -O /etc/syAgent/sh-agent.log -T 25 --post-data "$multipart_data" --no-check-certificate "https://agent.syagent.com/agent" &
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

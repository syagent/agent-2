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

function command_output() {
  if command -v "$1" >/dev/null 2>&1; then
    "$@" 2>/dev/null
  fi
}

function first_proc_value() {
  local key="$1"
  awk -F: -v key="$key" '$1 == key { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit }' /proc/cpuinfo 2>/dev/null
}

function count_proc_key() {
  local key="$1"
  grep -c "^$key" /proc/cpuinfo 2>/dev/null
}

function lscpu_value() {
  local key="$1"
  command_output lscpu | awk -F: -v key="$key" '$1 == key { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit }'
}

function sys_cpu_value() {
  local path="$1"
  if [ -r "$path" ]; then
    sed_rt "$(cat "$path")"
  fi
}

function normalize_mhz() {
  local value="$1"
  value=$(sed_rt "$value")
  value="${value/MHz/}"
  value="${value/mhz/}"
  value=$(sed_rt "$value")
  if [ -z "$value" ]; then
    echo "0"
    return
  fi
  to_num "$value"
}

function clean_kv_value() {
  local value
  value=$(sed_rt "$1")
  value=${value//,/ }
  value=${value//:/-}
  value=${value//;/ }
  if [ -z "$value" ]; then
    echo "N/A"
  else
    echo "$value"
  fi
}

function bool_text() {
  if [ "$1" = "true" ]; then
    echo "true"
  else
    echo "false"
  fi
}

version=$(sed_rt "$version")

uptime=$(sed_rt "$(to_int "$(cat /proc/uptime | awk '{ print $1 }')")")

sessions=$(sed_rt "$(who | wc -l)")

processes=$(sed_rt "$(ps axc | wc -l)")

function collect_processes_list() {
  {
    ps axc -o pid=,uname:12=,pcpu=,rss=,comm= --sort=-pcpu,-rss --noheaders --width 120 | head -n 8
    ps axc -o pid=,uname:12=,pcpu=,rss=,comm= --sort=-rss,-pcpu --noheaders --width 120 | head -n 8
  } | awk '
    $1 ~ /^[0-9]+$/ && $5 != "ps" && !seen[$1]++ && count < 15 {
      print $2" "$3" "$4" "$5";"
      count++
    }
  ' | tr -d '\n'
}

processes_list="$(collect_processes_list)"

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

machine_arch=$(uname -m)

case "$machine_arch" in
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

cpu_name=$(sed_rt "$(first_proc_value "model name")")
cpu_vendor=$(sed_rt "$(first_proc_value "vendor_id")")
cpu_hardware=$(sed_rt "$(first_proc_value "Hardware")")
cpu_implementer=$(sed_rt "$(first_proc_value "CPU implementer")")
cpu_part=$(sed_rt "$(first_proc_value "CPU part")")
cpu_revision=$(sed_rt "$(first_proc_value "CPU revision")")

if [ -z "$cpu_name" ]; then
  cpu_name=$(sed_rt "$(first_proc_value "Processor")")
fi

if [ -z "$cpu_name" ]; then
  cpu_name=$(sed_rt "$(lscpu_value "Model name")")
fi

if [ -z "$cpu_name" ] && [ -n "$cpu_hardware" ]; then
  cpu_name="$cpu_hardware"
fi

if [ -z "$cpu_name" ]; then
  cpu_name=$(sed_rt "$machine_arch")
fi

if [ -z "$cpu_vendor" ]; then
  cpu_vendor=$(sed_rt "$(lscpu_value "Vendor ID")")
fi

if [ -z "$cpu_vendor" ] && [ -n "$cpu_implementer" ]; then
  cpu_vendor="$cpu_implementer"
fi

if [ -z "$cpu_vendor" ]; then
  cpu_vendor="N/A"
fi

cpu_cores=$(sed_rt "$(count_proc_key "processor")")
if [ "$cpu_cores" = "0" ]; then
  cpu_cores=$(sed_rt "$(lscpu_value "CPU(s)")")
fi
cpu_cores=$(sed_rt "$(to_num "$cpu_cores")")

cpu_sockets=$(sed_rt "$(lscpu_value "Socket(s)")")
cpu_sockets=$(sed_rt "$(to_num "$cpu_sockets")")

cpu_freq=$(sed_rt "$(first_proc_value "cpu MHz")")
if [ -z "$cpu_freq" ]; then
  cpu_freq=$(sed_rt "$(lscpu_value "CPU MHz")")
fi
if [ -z "$cpu_freq" ]; then
  cpu_freq=$(sys_cpu_value /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
  if [ -n "$cpu_freq" ]; then
    cpu_freq=$((cpu_freq / 1000))
  fi
fi
cpu_freq=$(sed_rt "$(normalize_mhz "$cpu_freq")")

cpu_min_mhz=$(sed_rt "$(lscpu_value "CPU min MHz")")
if [ -z "$cpu_min_mhz" ]; then
  cpu_min_mhz=$(sys_cpu_value /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq)
  if [ -n "$cpu_min_mhz" ]; then
    cpu_min_mhz=$((cpu_min_mhz / 1000))
  fi
fi
cpu_min_mhz=$(sed_rt "$(normalize_mhz "$cpu_min_mhz")")

cpu_max_mhz=$(sed_rt "$(lscpu_value "CPU max MHz")")
if [ -z "$cpu_max_mhz" ]; then
  cpu_max_mhz=$(sys_cpu_value /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq)
  if [ -n "$cpu_max_mhz" ]; then
    cpu_max_mhz=$((cpu_max_mhz / 1000))
  fi
fi
cpu_max_mhz=$(sed_rt "$(normalize_mhz "$cpu_max_mhz")")

cpu_details="arch:$(clean_kv_value "$machine_arch"),vendor:$(clean_kv_value "$cpu_vendor"),model:$(clean_kv_value "$cpu_name"),hardware:$(clean_kv_value "$cpu_hardware"),implementer:$(clean_kv_value "$cpu_implementer"),part:$(clean_kv_value "$cpu_part"),revision:$(clean_kv_value "$cpu_revision"),threads:$(clean_kv_value "$cpu_cores"),sockets:$(clean_kv_value "$cpu_sockets"),min_mhz:$(clean_kv_value "$cpu_min_mhz"),max_mhz:$(clean_kv_value "$cpu_max_mhz")"

meminfo="$(cat /proc/meminfo 2>/dev/null)"

function meminfo_kb() {
  local key="$1"
  printf "%s\n" "$meminfo" | awk -F: -v key="$key" '$1 == key { gsub(/^[ \t]+/, "", $2); print $2 + 0; exit }'
}

function meminfo_bytes() {
  local value
  value=$(to_num "$(meminfo_kb "$1")")
  echo $((value * 1024))
}

ram_total=$(sed_rt "$(to_num "$(meminfo_kb "MemTotal")")")
ram_available=$(sed_rt "$(to_num "$(meminfo_kb "MemAvailable")")")

if [ "$ram_available" = "0" ]; then
  ram_free=$(sed_rt "$(to_num "$(meminfo_kb "MemFree")")")
  ram_cached=$(sed_rt "$(to_num "$(meminfo_kb "Cached")")")
  ram_buffers=$(sed_rt "$(to_num "$(meminfo_kb "Buffers")")")
  ram_available=$((ram_free + ram_cached + ram_buffers))
fi

ram_usage=$(((ram_total - ram_available) * 1024))
ram_total=$((ram_total * 1024))

swap_total=$(sed_rt "$(to_num "$(meminfo_kb "SwapTotal")")")
swap_free=$(sed_rt "$(to_num "$(meminfo_kb "SwapFree")")")
swap_usage=$(((swap_total - swap_free) * 1024))
swap_total=$((swap_total * 1024))

function psi_value() {
  local scope="$1"
  local field="$2"
  awk -v scope="$scope" -v field="$field" '
    $1 == scope {
      for (i = 2; i <= NF; i++) {
        split($i, pair, "=")
        if (pair[1] == field) {
          print pair[2]
          exit
        }
      }
    }
  ' /proc/pressure/memory 2>/dev/null
}

function vmstat_value() {
  local key="$1"
  awk -v key="$key" '$1 == key { print $2 + 0; exit }' /proc/vmstat 2>/dev/null
}

function vmstat_sum() {
  local total=0
  local key value
  for key in "$@"; do
    value=$(to_num "$(vmstat_value "$key")")
    total=$((total + value))
  done
  echo "$total"
}

function counter_rate() {
  local current="$1"
  local previous="$2"
  local interval="$3"
  if [ "$interval" -le 0 ] || [ "$current" -lt "$previous" ]; then
    echo "0"
    return
  fi
  awk -v current="$current" -v previous="$previous" -v interval="$interval" \
    'BEGIN { printf "%.3f", (current - previous) / interval }'
}

function collect_memory_details() {
  local now interval=0
  local pgfault pgmajfault pswpin pswpout pgscan pgsteal oom_kill
  local page_faults_per_sec=0 major_page_faults_per_sec=0
  local swap_in_pages_per_sec=0 swap_out_pages_per_sec=0
  local page_scans_per_sec=0 page_reclaims_per_sec=0 oom_kills_delta=0
  local vmstat_available=false
  local psi_available=false
  local psi_some_avg10=0 psi_some_avg60=0 psi_some_avg300=0
  local psi_full_avg10=0 psi_full_avg60=0 psi_full_avg300=0

  now=$(date +%s)
  if [ -r /proc/vmstat ]; then
    vmstat_available=true
  fi

  pgfault=$(to_num "$(vmstat_value "pgfault")")
  pgmajfault=$(to_num "$(vmstat_value "pgmajfault")")
  pswpin=$(to_num "$(vmstat_value "pswpin")")
  pswpout=$(to_num "$(vmstat_value "pswpout")")
  pgscan=$(vmstat_sum "pgscan_kswapd" "pgscan_direct" "pgscan_khugepaged")
  pgsteal=$(vmstat_sum "pgsteal_kswapd" "pgsteal_direct" "pgsteal_khugepaged")
  oom_kill=$(to_num "$(vmstat_value "oom_kill")")

  if [ -r /etc/syAgent/memory-data.log ]; then
    local previous_time previous_pgfault previous_pgmajfault previous_pswpin previous_pswpout
    local previous_pgscan previous_pgsteal previous_oom_kill
    read -r previous_time previous_pgfault previous_pgmajfault previous_pswpin previous_pswpout \
      previous_pgscan previous_pgsteal previous_oom_kill < /etc/syAgent/memory-data.log
    previous_time=$(to_num "$previous_time")
    interval=$((now - previous_time))

    if [ "$interval" -gt 0 ]; then
      page_faults_per_sec=$(counter_rate "$pgfault" "$(to_num "$previous_pgfault")" "$interval")
      major_page_faults_per_sec=$(counter_rate "$pgmajfault" "$(to_num "$previous_pgmajfault")" "$interval")
      swap_in_pages_per_sec=$(counter_rate "$pswpin" "$(to_num "$previous_pswpin")" "$interval")
      swap_out_pages_per_sec=$(counter_rate "$pswpout" "$(to_num "$previous_pswpout")" "$interval")
      page_scans_per_sec=$(counter_rate "$pgscan" "$(to_num "$previous_pgscan")" "$interval")
      page_reclaims_per_sec=$(counter_rate "$pgsteal" "$(to_num "$previous_pgsteal")" "$interval")
      if [ "$oom_kill" -ge "$(to_num "$previous_oom_kill")" ]; then
        oom_kills_delta=$((oom_kill - previous_oom_kill))
      fi
    fi
  fi

  echo "$now $pgfault $pgmajfault $pswpin $pswpout $pgscan $pgsteal $oom_kill" >/etc/syAgent/memory-data.log

  if [ -r /proc/pressure/memory ]; then
    psi_available=true
    psi_some_avg10=$(to_num "$(psi_value "some" "avg10")")
    psi_some_avg60=$(to_num "$(psi_value "some" "avg60")")
    psi_some_avg300=$(to_num "$(psi_value "some" "avg300")")
    psi_full_avg10=$(to_num "$(psi_value "full" "avg10")")
    psi_full_avg60=$(to_num "$(psi_value "full" "avg60")")
    psi_full_avg300=$(to_num "$(psi_value "full" "avg300")")
  fi

  echo "available_bytes:$((ram_available * 1024)),free_bytes:$(meminfo_bytes "MemFree"),buffers_bytes:$(meminfo_bytes "Buffers"),cached_bytes:$(meminfo_bytes "Cached"),active_bytes:$(meminfo_bytes "Active"),inactive_bytes:$(meminfo_bytes "Inactive"),anonymous_bytes:$(meminfo_bytes "AnonPages"),slab_bytes:$(meminfo_bytes "Slab"),reclaimable_bytes:$(meminfo_bytes "SReclaimable"),shared_bytes:$(meminfo_bytes "Shmem"),dirty_bytes:$(meminfo_bytes "Dirty"),writeback_bytes:$(meminfo_bytes "Writeback"),page_tables_bytes:$(meminfo_bytes "PageTables"),kernel_stack_bytes:$(meminfo_bytes "KernelStack"),commit_limit_bytes:$(meminfo_bytes "CommitLimit"),committed_bytes:$(meminfo_bytes "Committed_AS"),vmstat_available:$vmstat_available,psi_available:$psi_available,psi_some_avg10:$psi_some_avg10,psi_some_avg60:$psi_some_avg60,psi_some_avg300:$psi_some_avg300,psi_full_avg10:$psi_full_avg10,psi_full_avg60:$psi_full_avg60,psi_full_avg300:$psi_full_avg300,page_faults_per_sec:$page_faults_per_sec,major_page_faults_per_sec:$major_page_faults_per_sec,swap_in_pages_per_sec:$swap_in_pages_per_sec,swap_out_pages_per_sec:$swap_out_pages_per_sec,page_scans_per_sec:$page_scans_per_sec,page_reclaims_per_sec:$page_reclaims_per_sec,oom_kills_delta:$oom_kills_delta"
}

memory_details=$(collect_memory_details)

disk_total=$(sed_rt "$(to_num "$(($(df -P -B 1 | grep '^/' | awk '{ print $2 }' | sed -e :a -e '$!N;s/\n/+/;ta')))")")
disk_usage=$(sed_rt "$(to_num "$(($(df -P -B 1 | grep '^/' | awk '{ print $3 }' | sed -e :a -e '$!N;s/\n/+/;ta')))")")

disk_array=$(sed_rt "$(df -P -B 1 | grep '^/' | awk '{ print $1" "$2" "$3";" }' | sed -e :a -e '$!N;s/\n/ /;ta' | awk '{ print $0 } END { if (!NR) print "N/A" }')")

function disk_base_name() {
  local device="$1"

  if [ -d "/sys/block/$device" ]; then
    echo "$device"
    return
  fi

  while [ -n "$device" ]; do
    device="${device%[0-9]}"
    device="${device%p}"
    if [ -d "/sys/block/$device" ]; then
      echo "$device"
      return
    fi
    break
  done
}

function disk_sector_size() {
  local base="$1"

  if [ -r "/sys/block/$base/queue/logical_block_size" ]; then
    cat "/sys/block/$base/queue/logical_block_size"
  else
    echo 512
  fi
}

function should_skip_disk_device() {
  case "$1" in
    loop*|ram*|fd*|sr*) return 0 ;;
    *) return 1 ;;
  esac
}

function collect_disk_snapshot() {
  # /proc/diskstats: 3=name, 4=reads completed, 6=sectors read, 8=writes completed, 10=sectors written, 13=io_time(ms), 14=weighted_io_time(ms)
  awk '{ print $3" "$4" "$6" "$8" "$10" "$13" "$14 }' /proc/diskstats 2>/dev/null
}

function previous_disk_line() {
  local device="$1"
  if [ -r /etc/syAgent/disk-data.log ]; then
    awk -v device="$device" '$1 == device { print; exit }' /etc/syAgent/disk-data.log
  fi
}

function collect_disk_io() {
  local now="$1"
  local disk_io=""
  local snapshot=""

  snapshot="$(collect_disk_snapshot)"

  while read -r device reads sectors_read writes sectors_written io_time weighted_io_time; do
    if [ -z "$device" ] || should_skip_disk_device "$device"; then
      continue
    fi

    local base sector_size total_read_bytes total_write_bytes
    base=$(disk_base_name "$device")
    if [ -z "$base" ]; then
      continue
    fi

    sector_size=$(disk_sector_size "$base")
    total_read_bytes=$((sectors_read * sector_size))
    total_write_bytes=$((sectors_written * sector_size))

    local read_bps=0 write_bps=0 read_iops=0 write_iops=0 busy_percent=0
    local previous previous_time previous_reads previous_sectors_read previous_writes previous_sectors_written previous_io_time
    previous="$(previous_disk_line "$device")"
    if [ -n "$previous" ]; then
      read -r _ previous_time previous_reads previous_sectors_read previous_writes previous_sectors_written previous_io_time _ <<< "$previous"
      local interval=$((now - previous_time))
      if [ "$interval" -gt 0 ]; then
        local read_delta=$((reads - previous_reads))
        local write_delta=$((writes - previous_writes))
        local sectors_read_delta=$((sectors_read - previous_sectors_read))
        local sectors_written_delta=$((sectors_written - previous_sectors_written))
        local io_time_delta=$((io_time - previous_io_time))

        if [ "$read_delta" -gt 0 ]; then
          read_iops=$((read_delta / interval))
        fi
        if [ "$write_delta" -gt 0 ]; then
          write_iops=$((write_delta / interval))
        fi
        if [ "$sectors_read_delta" -gt 0 ]; then
          read_bps=$((sectors_read_delta * sector_size / interval))
        fi
        if [ "$sectors_written_delta" -gt 0 ]; then
          write_bps=$((sectors_written_delta * sector_size / interval))
        fi
        if [ "$io_time_delta" -gt 0 ]; then
          busy_percent=$((io_time_delta / (interval * 10)))
          if [ "$busy_percent" -gt 100 ]; then
            busy_percent=100
          fi
        fi
      fi
    fi

    disk_io="$disk_io""name:$(clean_kv_value "$device"),read_bytes_per_sec:$read_bps,write_bytes_per_sec:$write_bps,read_iops:$read_iops,write_iops:$write_iops,busy_percent:$busy_percent,total_read_bytes:$total_read_bytes,total_write_bytes:$total_write_bytes;"
  done <<< "$snapshot"

  printf "%s\n" "$snapshot" | awk -v now="$now" '{ print $1" "now" "$2" "$3" "$4" "$5" "$6" "$7 }' >/etc/syAgent/disk-data.log
  echo "$disk_io"
}

function collect_raid_details() {
  local raid_details=""

  if [ -r /proc/mdstat ]; then
    while read -r line; do
      case "$line" in
        md*:*active*)
          local name level status active_devices total_devices failed_devices spare_devices
          name=$(echo "$line" | awk -F: '{ print $1 }' | sed -e 's/^ *//g' -e 's/ *$//g')
          level=$(echo "$line" | awk '{ for (i=1; i<=NF; i++) if ($i ~ /^raid/) { print $i; exit } }')
          active_devices=$(echo "$line" | grep -o '\[[0-9]\+\]' | tail -n 1 | tr -d '[]')
          total_devices=$(echo "$line" | grep -o '\[[0-9]\+/[0-9]\+\]' | tail -n 1 | awk -F'[][]|/' '{ print $2 }')
          failed_devices=0
          spare_devices=$(echo "$line" | grep -o '(S)' | wc -l)
          status="active"

          if echo "$line" | grep -q "_"; then
            status="degraded"
          fi
          if [ -z "$active_devices" ]; then
            active_devices=0
          fi
          if [ -z "$total_devices" ]; then
            total_devices="$active_devices"
          fi

          raid_details="$raid_details""name:$(clean_kv_value "$name"),type:md,level:$(clean_kv_value "$level"),status:$(clean_kv_value "$status"),active_devices:$(to_num "$active_devices"),total_devices:$(to_num "$total_devices"),failed_devices:$failed_devices,spare_devices:$(to_num "$spare_devices");"
          ;;
      esac
    done < /proc/mdstat
  fi

  if [ -n "$(command -v lsblk)" ]; then
    while read -r name type; do
      if [ "$type" = "lvm" ] || [ "$type" = "crypt" ] || [ "$type" = "dmraid" ]; then
        raid_details="$raid_details""name:$(clean_kv_value "$name"),type:$(clean_kv_value "$type"),level:N/A,status:active,active_devices:0,total_devices:0,failed_devices:0,spare_devices:0;"
      fi
    done <<< "$(lsblk -rno NAME,TYPE 2>/dev/null)"
  fi

  echo "$raid_details"
}

disk_io=$(collect_disk_io "$(date +%s)")
raid_details=$(collect_raid_details)




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

function add_app() {
  local name="$1"
  local version="$2"

  version=$(clean_kv_value "$version")
  if [ "$version" = "N/A" ]; then
    return
  fi

  if [ -n "$apps_info" ]; then
    apps_info="$apps_info,"
  fi
  apps_info="$apps_info$name:$version"
}

apps_info=""

add_app "nginx_version" "$(get_command_version 3 nginx -v)"
add_app "apache_version" "$(get_command_version 3 httpd -v)"
add_app "mysql_version" "$(get_command_version 3 mysql --version)"
add_app "postgres_version" "$(get_command_version 3 psql --version)"
add_app "mongo_version" "$(get_command_version 3 mongo --version)"
add_app "php_version" "$(get_command_version 2 php -v)"
add_app "docker_version" "$(get_command_version 3 docker -v)"
add_app "python_version" "$(get_command_version 2 python --version)"
add_app "python3_version" "$(get_command_version 2 python3 --version)"
add_app "pip_version" "$(get_command_version 2 pip --version)"
add_app "pip3_version" "$(get_command_version 2 pip3 --version)"
add_app "perl_version" "$(get_command_version 4 perl --version)"
add_app "ruby_version" "$(get_command_version 2 ruby --version)"
add_app "java_version" "$(get_command_version 2 java --version)"
add_app "gcc_version" "$(get_command_version 3 gcc --version)"
add_app "gpp_version" "$(get_command_version 3 g++ --version)"
add_app "redis_version" "$(get_command_version 3 redis-server --version)"
add_app "kafka_version" "$(get_command_version 3 kafka-server --version)"
add_app "rabbitmq_version" "$(get_command_version 2 rabbitmq --version)"
add_app "nodejs_version" "$(get_command_version 1 node --version)"
add_app "npm_version" "$(get_command_version 1 npm --version)"
add_app "yarn_version" "$(get_command_version 1 yarn --version)"
add_app "pnpm_version" "$(get_command_version 1 pnpm --version)"
add_app "go_version" "$(get_command_version 3 go version)"
add_app "rustc_version" "$(get_command_version 2 rustc --version)"
add_app "cargo_version" "$(get_command_version 2 cargo --version)"
add_app "dotnet_version" "$(get_command_version 1 dotnet --version)"
add_app "composer_version" "$(get_command_version 3 composer --version)"
add_app "caddy_version" "$(get_command_version 1 caddy version)"
add_app "traefik_version" "$(get_command_version 3 traefik version)"
add_app "haproxy_version" "$(get_command_version 3 haproxy -v)"
add_app "certbot_version" "$(get_command_version 2 certbot --version)"
add_app "mariadb_version" "$(get_command_version 3 mariadb --version)"
add_app "sqlite3_version" "$(get_command_version 1 sqlite3 --version)"
add_app "memcached_version" "$(get_command_version 2 memcached -V)"
add_app "elasticsearch_version" "$(get_command_version 2 elasticsearch --version)"
add_app "opensearch_version" "$(get_command_version 2 opensearch --version)"
add_app "git_version" "$(get_command_version 3 git --version)"
add_app "docker_compose_version" "$(get_command_version 4 docker-compose --version)"
add_app "podman_version" "$(get_command_version 3 podman --version)"
add_app "containerd_version" "$(get_command_version 3 containerd --version)"
add_app "kubectl_version" "$(get_command_version 3 kubectl version --client=true)"
add_app "helm_version" "$(get_command_version 3 helm version --short)"
add_app "pm2_version" "$(get_command_version 2 pm2 --version)"
add_app "supervisord_version" "$(get_command_version 2 supervisord --version)"
add_app "fail2ban_version" "$(get_command_version 2 fail2ban-client --version)"
add_app "ufw_version" "$(get_command_version 2 ufw --version)"
add_app "firewalld_version" "$(get_command_version 2 firewall-cmd --version)"

function first_available_file() {
  for path in "$@"; do
    if [ -r "$path" ]; then
      sed_rt "$(cat "$path")"
      return
    fi
  done
}

function detect_package_manager() {
  for package_manager in apt-get dnf yum pacman zypper apk emerge; do
    if command -v "$package_manager" >/dev/null 2>&1; then
      echo "$package_manager"
      return
    fi
  done
  echo "N/A"
}

function detect_cloud_vendor() {
  local vendor="$1"
  local product="$2"
  local combined
  combined=$(printf "%s %s" "$vendor" "$product" | tr '[:upper:]' '[:lower:]')

  case "$combined" in
    *amazon*|*ec2*) echo "aws" ;;
    *google*|*gce*) echo "gcp" ;;
    *microsoft*|*azure*) echo "azure" ;;
    *digitalocean*) echo "digitalocean" ;;
    *linode*) echo "linode" ;;
    *vultr*) echo "vultr" ;;
    *hetzner*) echo "hetzner" ;;
    *oracle*) echo "oracle" ;;
    *alibaba*) echo "alibaba" ;;
    *openstack*) echo "openstack" ;;
    *) echo "N/A" ;;
  esac
}

hostname_value=$(sed_rt "$(command_output hostname)")
if [ -z "$hostname_value" ]; then
  hostname_value=$(sed_rt "$(uname -n)")
fi

timezone_value=$(sed_rt "$(command_output timedatectl show -p Timezone --value)")
if [ -z "$timezone_value" ]; then
  timezone_value=$(first_available_file /etc/timezone)
fi
if [ -z "$timezone_value" ]; then
  timezone_value=$(date +%Z)
fi

virtualization_value=$(sed_rt "$(command_output systemd-detect-virt --vm)")
if [ -z "$virtualization_value" ]; then
  virtualization_value="N/A"
fi

container_value=$(sed_rt "$(command_output systemd-detect-virt --container)")
if [ -z "$container_value" ]; then
  if [ -f /.dockerenv ]; then
    container_value="docker"
  elif [ -f /run/.containerenv ]; then
    container_value="podman"
  else
    container_value="N/A"
  fi
fi

dmi_vendor=$(first_available_file /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/board_vendor)
dmi_product=$(first_available_file /sys/class/dmi/id/product_name)
cloud_vendor=$(detect_cloud_vendor "$dmi_vendor" "$dmi_product")

machine_id_present=false
if [ -s /etc/machine-id ] || [ -s /var/lib/dbus/machine-id ]; then
  machine_id_present=true
fi

boot_mode="bios"
if [ -d /sys/firmware/efi ]; then
  boot_mode="uefi"
fi

package_manager=$(detect_package_manager)

reboot_required=false
if [ -f /var/run/reboot-required ] || [ -f /run/reboot-required ] || [ -f /var/run/needs-restarting ]; then
  reboot_required=true
fi

host_details="hostname:$(clean_kv_value "$hostname_value"),timezone:$(clean_kv_value "$timezone_value"),virtualization:$(clean_kv_value "$virtualization_value"),container:$(clean_kv_value "$container_value"),cloud_vendor:$(clean_kv_value "$cloud_vendor"),machine_id_present:$(bool_text "$machine_id_present"),boot_mode:$(clean_kv_value "$boot_mode"),package_manager:$(clean_kv_value "$package_manager"),reboot_required:$(bool_text "$reboot_required")"


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

multipart_data="token=$token&data=$(to_base64 "$version") $(to_base64 "$uptime") $(to_base64 "$sessions") $(to_base64 "$processes") $(to_base64 "$processes_list") $(to_base64 "$file_handles") $(to_base64 "$file_handles_limit") $(to_base64 "$os_kernel") $(to_base64 "$os_name") $(to_base64 "$os_arch") $(to_base64 "$cpu_name") $(to_base64 "$cpu_cores") $(to_base64 "$cpu_freq") $(to_base64 "$ram_total") $(to_base64 "$ram_usage") $(to_base64 "$swap_total") $(to_base64 "$swap_usage") $(to_base64 "$disk_array") $(to_base64 "$disk_total") $(to_base64 "$disk_usage") $(to_base64 "$connections") $(to_base64 "$nic") $(to_base64 "$ipv4") $(to_base64 "$ipv6") $(to_base64 "$rx") $(to_base64 "$tx") $(to_base64 "$rx_gap") $(to_base64 "$tx_gap") $(to_base64 "$load") $(to_base64 "$load_cpu") $(to_base64 "$load_io") $(to_base64 "$apps_info") $(to_base64 "success_attempts:$success_attempts,failed_attempts:$failed_attempts") $(to_base64 "$gpu_info") $(to_base64 "$gpu_procs_info") $(to_base64 "$cpu_details") $(to_base64 "$host_details") $(to_base64 "$disk_io") $(to_base64 "$raid_details") $(to_base64 "$memory_details")"

if [ "$dry_run" = true ]; then
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

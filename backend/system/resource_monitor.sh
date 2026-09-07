#!/usr/bin/env bash
# Resource Monitor
# Monitors system resources (CPU, memory, disk, processes)

# Prevent multiple sourcing
[[ -n "${RESOURCE_MONITOR_LOADED:-}" ]] && return 0
readonly RESOURCE_MONITOR_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/../../config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/logger.sh"

# =============================================================================
# RESOURCE MONITOR
# =============================================================================

# Monitor interval
MONITOR_INTERVAL="${RESOURCE_MONITOR_INTERVAL:-5}"

# Get CPU usage percentage
get_cpu_usage() {
    # Read /proc/stat
    local stat1=$(grep '^cpu ' /proc/stat 2>/dev/null)
    sleep 0.1
    local stat2=$(grep '^cpu ' /proc/stat 2>/dev/null)
    
    if [[ -n "$stat1" && -n "$stat2" ]]; then
        local idle1=$(echo "$stat1" | awk '{print $5}')
        local idle2=$(echo "$stat2" | awk '{print $5}')
        local total1=$(echo "$stat1" | awk '{sum=0; for(i=2;i<=NF;i++) sum+=$i; print sum}')
        local total2=$(echo "$stat2" | awk '{sum=0; for(i=2;i<=NF;i++) sum+=$i; print sum}')
        
        local idle_diff=$((idle2 - idle1))
        local total_diff=$((total2 - total1))
        
        if [[ $total_diff -gt 0 ]]; then
            local usage=$((100 * (total_diff - idle_diff) / total_diff))
            echo "$usage"
        else
            echo "0"
        fi
    else
        echo "0"
    fi
}

# Get memory usage
get_memory_usage() {
    if [[ -f /proc/meminfo ]]; then
        local total=$(grep 'MemTotal:' /proc/meminfo | awk '{print $2}')
        local available=$(grep 'MemAvailable:' /proc/meminfo | awk '{print $2}')
        
        if [[ -n "$total" && -n "$available" && $total -gt 0 ]]; then
            local used=$((total - available))
            local usage=$((100 * used / total))
            json_object \
                "total_kb" "$total" \
                "available_kb" "$available" \
                "used_kb" "$used" \
                "usage_percent" "$usage"
        else
            json_object "total_kb" "0" "available_kb" "0" "used_kb" "0" "usage_percent" "0"
        fi
    else
        json_object "total_kb" "0" "available_kb" "0" "used_kb" "0" "usage_percent" "0"
    fi
}

# Get disk usage
get_disk_usage() {
    local path="${1:-/}"
    local df_output=$(df -k "$path" 2>/dev/null | tail -1)
    
    if [[ -n "$df_output" ]]; then
        local total=$(echo "$df_output" | awk '{print $2}')
        local used=$(echo "$df_output" | awk '{print $3}')
        local available=$(echo "$df_output" | awk '{print $4}')
        local usage=$(echo "$df_output" | awk '{print $5}' | sed 's/%//')
        
        json_object \
            "total_kb" "$total" \
            "used_kb" "$used" \
            "available_kb" "$available" \
            "usage_percent" "$usage"
    else
        json_object "total_kb" "0" "used_kb" "0" "available_kb" "0" "usage_percent" "0"
    fi
}

# Get system uptime
get_system_uptime() {
    if [[ -f /proc/uptime ]]; then
        local uptime_sec=$(cat /proc/uptime | awk '{print int($1)}')
        local days=$((uptime_sec / 86400))
        local hours=$(( (uptime_sec % 86400) / 3600 ))
        local minutes=$(( (uptime_sec % 3600) / 60 ))
        
        json_object \
            "seconds" "$uptime_sec" \
            "formatted" "$(printf "%dd %dh %dm" "$days" "$hours" "$minutes")"
    else
        json_object "seconds" "0" "formatted" "unknown"
    fi
}

# Get process count
get_process_count() {
    local total=$(ps aux 2>/dev/null | wc -l)
    local our_processes=0
    
    # Count our processes
    for pid_file in "${PIDS_DIR}"/*.pid; do
        [[ -f "$pid_file" ]] || continue
        local pid=$(cat "$pid_file")
        kill -0 "$pid" 2>/dev/null && ((our_processes++))
    done
    
    json_object \
        "total" "$total" \
        "our_processes" "$our_processes"
}

# Get load average
get_load_average() {
    if [[ -f /proc/loadavg ]]; then
        local load=$(cat /proc/loadavg)
        local load1=$(echo "$load" | awk '{print $1}')
        local load5=$(echo "$load" | awk '{print $2}')
        local load15=$(echo "$load" | awk '{print $3}')
        
        json_object \
            "1min" "$load1" \
            "5min" "$load5" \
            "15min" "$load15"
    else
        json_object "1min" "0" "5min" "0" "15min" "0"
    fi
}

# Get network stats (basic)
get_network_stats() {
    if [[ -f /proc/net/dev ]]; then
        local rx_bytes=0
        local tx_bytes=0
        
        while read -r line; do
            if [[ "$line" =~ ^[[:space:]]*[a-zA-Z0-9]+: ]]; then
                local rx=$(echo "$line" | awk '{print $2}')
                local tx=$(echo "$line" | awk '{print $10}')
                rx_bytes=$((rx_bytes + rx))
                tx_bytes=$((tx_bytes + tx))
            fi
        done < /proc/net/dev
        
        json_object \
            "rx_bytes" "$rx_bytes" \
            "tx_bytes" "$tx_bytes"
    else
        json_object "rx_bytes" "0" "tx_bytes" "0"
    fi
}

# Get all resources
get_all_resources() {
    local cpu=$(get_cpu_usage)
    local memory=$(get_memory_usage)
    local disk=$(get_disk_usage)
    local uptime=$(get_system_uptime)
    local processes=$(get_process_count)
    local load=$(get_load_average)
    local network=$(get_network_stats)
    
    json_object \
        "cpu_usage_percent" "$cpu" \
        "memory" "$memory" \
        "disk" "$disk" \
        "uptime" "$uptime" \
        "processes" "$processes" \
        "load_average" "$load" \
        "network" "$network" \
        "timestamp" "$(get_timestamp)"
}

# Monitor loop
monitor_loop() {
    log_system "Resource monitor started (interval: ${MONITOR_INTERVAL}s)"
    
    while true; do
        local resources=$(get_all_resources)
        
        # Log to system log (could also write to dedicated file)
        log_system "Resources: CPU=$(echo "$resources" | jq -r '.cpu_usage_percent')% Mem=$(echo "$resources" | jq -r '.memory.usage_percent')% Procs=$(echo "$resources" | jq -r '.processes.total')"
        
        # Save to file for frontend
        atomic_write "${STATS_DIR}/resources.json" "$resources"
        
        sleep "$MONITOR_INTERVAL"
    done
}

# One-shot resource check
resource_check() {
    get_all_resources
}

# Export functions
export -f get_cpu_usage get_memory_usage get_disk_usage get_system_uptime
export -f get_process_count get_load_average get_network_stats
export -f get_all_resources monitor_loop resource_check
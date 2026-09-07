#!/usr/bin/env bash
# Process Manager System Module
# High-level process management with CLI interface

# Prevent multiple sourcing
[[ -n "${PROCESS_MANAGER_LOADED:-}" ]] && return 0
readonly PROCESS_MANAGER_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/../../config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../processes/manager.sh"

# =============================================================================
# PROCESS MANAGER SYSTEM
# =============================================================================

# Start system with default processes
system_start() {
    local producers="${1:-$DEFAULT_PRODUCERS}"
    local workers="${2:-$DEFAULT_WORKERS}"
    
    log_system "Starting system with $producers producers and $workers workers"
    
    # Initialize
    init_directories
    stats_init
    
    # Create FIFOs
    fifo_create_all
    
    # Start manager in background
    "${PROJECT_ROOT}/backend/processes/manager.sh" &
    local manager_pid=$!
    save_pid "manager" "$manager_pid"
    
    # Wait for manager to start
    sleep 2
    
    # Start producers
    for i in $(seq 1 "$producers"); do
        start_producer "producer-$i"
    done
    
    # Start workers
    for i in $(seq 1 "$workers"); do
        start_worker "worker-$i"
    done
    
    log_system "System started successfully"
}

# Stop system gracefully
system_stop() {
    log_system "Stopping system..."
    
    # Stop manager (which stops all processes)
    local manager_pid=$(load_pid "manager")
    if [[ -n "$manager_pid" ]] && kill -0 "$manager_pid" 2>/dev/null; then
        kill -TERM "$manager_pid"
        wait "$manager_pid" 2>/dev/null || true
    fi
    
    # Cleanup
    system_cleanup
    
    log_system "System stopped"
}

# Restart system
system_restart() {
    system_stop
    sleep 2
    system_start "$@"
}

# Get system status
system_status() {
    local manager_pid=$(load_pid "manager")
    local manager_status="STOPPED"
    [[ -n "$manager_pid" ]] && kill -0 "$manager_pid" 2>/dev/null && manager_status="RUNNING"
    
    local producers=$(list_producers | wc -l)
    local workers=$(list_workers | wc -l)
    local running_producers=$(list_producers | grep -c "RUNNING" || echo 0)
    local running_workers=$(list_workers | grep -c "RUNNING" || echo 0)
    
    json_object \
        "manager" "$(json_object "pid" "$manager_pid" "status" "$manager_status")" \
        "producers" "$(json_object "total" "$producers" "running" "$running_producers")" \
        "workers" "$(json_object "total" "$workers" "running" "$running_workers")" \
        "timestamp" "$(get_timestamp)"
}

# Scale producers
scale_producers() {
    local target="$1"
    local current=$(list_producers | wc -l)
    
    if [[ $target -gt $current ]]; then
        for i in $(seq $((current + 1)) "$target"); do
            start_producer "producer-$i"
        done
    elif [[ $target -lt $current ]]; then
        for i in $(seq $((target + 1)) "$current"); do
            stop_producer "producer-$i"
        done
    fi
    
    log_system "Scaled producers to $target"
}

# Scale workers
scale_workers() {
    local target="$1"
    local current=$(list_workers | wc -l)
    
    if [[ $target -gt $current ]]; then
        for i in $(seq $((current + 1)) "$target"); do
            start_worker "worker-$i"
        done
    elif [[ $target -lt $current ]]; then
        for i in $(seq $((target + 1)) "$current"); do
            stop_worker "worker-$i"
        done
    fi
    
    log_system "Scaled workers to $target"
}

# Health check
system_health() {
    local issues=()
    
    # Check manager
    local manager_pid=$(load_pid "manager")
    if [[ -z "$manager_pid" ]] || ! kill -0 "$manager_pid" 2>/dev/null; then
        issues+=("Manager not running")
    fi
    
    # Check producers
    local dead_producers=0
    for pid_file in "${PIDS_DIR}"/producer-*.pid; do
        [[ -f "$pid_file" ]] || continue
        local pid=$(cat "$pid_file")
        if ! kill -0 "$pid" 2>/dev/null; then
            ((dead_producers++))
        fi
    done
    [[ $dead_producers -gt 0 ]] && issues+=("$dead_producers dead producers")
    
    # Check workers
    local dead_workers=0
    for pid_file in "${PIDS_DIR}"/worker-*.pid; do
        [[ -f "$pid_file" ]] || continue
        local pid=$(cat "$pid_file")
        if ! kill -0 "$pid" 2>/dev/null; then
            ((dead_workers++))
        fi
    done
    [[ $dead_workers -gt 0 ]] && issues+=("$dead_workers dead workers")
    
    # Check FIFOs
    [[ -p "$PRODUCER_FIFO" ]] || issues+=("Producer FIFO missing")
    [[ -p "$WORKER_FIFO" ]] || issues+=("Worker FIFO missing")
    [[ -p "$CONTROL_FIFO" ]] || issues+=("Control FIFO missing")
    
    # Check queue
    local queue_size=$(queue_size)
    [[ $queue_size -gt $((QUEUE_MAX_SIZE * 90 / 100)) ]] && issues+=("Queue near capacity: $queue_size/$QUEUE_MAX_SIZE")
    
    local status="HEALTHY"
    [[ ${#issues[@]} -gt 0 ]] && status="DEGRADED"
    [[ ${#issues[@]} -gt 5 ]] && status="UNHEALTHY"
    
    json_object \
        "status" "$status" \
        "issues" "$(json_array "${issues[@]}")" \
        "timestamp" "$(get_timestamp)"
}

# Export functions
export -f system_start system_stop system_restart system_status
export -f scale_producers scale_workers system_health
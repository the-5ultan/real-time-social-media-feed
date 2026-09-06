#!/usr/bin/env bash
# Process Manager
# Manages producer and worker processes lifecycle

set -Eeuo pipefail

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "${PROJECT_ROOT}/backend/config.sh"
source "${PROJECT_ROOT}/backend/utils/common.sh"
source "${PROJECT_ROOT}/backend/utils/logger.sh"
source "${PROJECT_ROOT}/backend/services/statistics_service.sh"

# =============================================================================
# MANAGER CONFIGURATION
# =============================================================================

MANAGER_POLL_INTERVAL="${MANAGER_POLL_INTERVAL:-1}"
DEFAULT_PRODUCERS="${DEFAULT_PRODUCERS:-3}"
DEFAULT_WORKERS="${DEFAULT_WORKERS:-2}"

# =============================================================================
# MANAGER FUNCTIONS
# =============================================================================

# Initialize manager
manager_init() {
    log_process "manager" "START" "$$" "Process manager initialized"
    stats_init
    
    # Setup signal handlers
    trap 'manager_shutdown' EXIT INT TERM
}

# Shutdown manager
manager_shutdown() {
    log_process "manager" "STOP" "$$" "Process manager shutting down"
    
    # Stop all managed processes
    stop_all_producers
    stop_all_workers
}

# Start producer
start_producer() {
    local producer_name="${1:-producer-$(( $(list_producers | wc -l) + 1 ))}"
    
    # Check if already running
    local existing_pid=$(load_pid "$producer_name")
    if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
        log_warn "Producer $producer_name already running (PID: $existing_pid)"
        return 0
    fi
    
    "${PROJECT_ROOT}/backend/processes/producer.sh" "$producer_name" &
    local pid=$!
    save_pid "$producer_name" "$pid"
    log_process "$producer_name" "START" "$pid" "Producer started"
    stats_increment "active_producers"
}

# Start worker
start_worker() {
    local worker_name="${1:-worker-$(( $(list_workers | wc -l) + 1 ))}"
    
    # Check if already running
    local existing_pid=$(load_pid "$worker_name")
    if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
        log_warn "Worker $worker_name already running (PID: $existing_pid)"
        return 0
    fi
    
    "${PROJECT_ROOT}/backend/processes/worker.sh" "$worker_name" &
    local pid=$!
    save_pid "$worker_name" "$pid"
    log_process "$worker_name" "START" "$pid" "Worker started"
    stats_increment "active_workers"
}

# Stop producer
stop_producer() {
    local producer_name="$1"
    local pid=$(load_pid "$producer_name")
    
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill_graceful "$pid" 5
        log_process "$producer_name" "STOP" "$pid" "Producer stopped"
        stats_decrement "active_producers"
    fi
    remove_pid "$producer_name"
}

# Stop worker
stop_worker() {
    local worker_name="$1"
    local pid=$(load_pid "$worker_name")
    
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill_graceful "$pid" 5
        log_process "$worker_name" "STOP" "$pid" "Worker stopped"
        stats_decrement "active_workers"
    fi
    remove_pid "$worker_name"
}

# Stop all producers
stop_all_producers() {
    for pid_file in "${PIDS_DIR}"/producer-*.pid; do
        [[ -f "$pid_file" ]] || continue
        local name=$(basename "$pid_file" .pid)
        stop_producer "$name"
    done
}

# Stop all workers
stop_all_workers() {
    for pid_file in "${PIDS_DIR}"/worker-*.pid; do
        [[ -f "$pid_file" ]] || continue
        local name=$(basename "$pid_file" .pid)
        stop_worker "$name"
    done
}

# List producers
list_producers() {
    for pid_file in "${PIDS_DIR}"/producer-*.pid; do
        [[ -f "$pid_file" ]] || continue
        local name=$(basename "$pid_file" .pid)
        local pid=$(cat "$pid_file")
        local status="STOPPED"
        kill -0 "$pid" 2>/dev/null && status="RUNNING"
        echo "$name:$pid:$status"
    done
}

# List workers
list_workers() {
    for pid_file in "${PIDS_DIR}"/worker-*.pid; do
        [[ -f "$pid_file" ]] || continue
        local name=$(basename "$pid_file" .pid)
        local pid=$(cat "$pid_file")
        local status="STOPPED"
        kill -0 "$pid" 2>/dev/null && status="RUNNING"
        echo "$name:$pid:$status"
    done
}

# List all processes
list_all_processes() {
    echo "=== Producers ==="
    list_producers
    echo "=== Workers ==="
    list_workers
}

# Check and restart dead processes
monitor_processes() {
    # Check producers
    for pid_file in "${PIDS_DIR}"/producer-*.pid; do
        [[ -f "$pid_file" ]] || continue
        local name=$(basename "$pid_file" .pid)
        local pid=$(cat "$pid_file")
        
        if ! kill -0 "$pid" 2>/dev/null; then
            log_warn "Producer $name (PID: $pid) died, restarting..."
            remove_pid "$name"
            stats_decrement "active_producers"
            start_producer "$name"
        fi
    done
    
    # Check workers
    for pid_file in "${PIDS_DIR}"/worker-*.pid; do
        [[ -f "$pid_file" ]] || continue
        local name=$(basename "$pid_file" .pid)
        local pid=$(cat "$pid_file")
        
        if ! kill -0 "$pid" 2>/dev/null; then
            log_warn "Worker $name (PID: $pid) died, restarting..."
            remove_pid "$name"
            stats_decrement "active_workers"
            start_worker "$name"
        fi
    done
}

# Get process status for frontend
get_process_status() {
    local result="["
    local first=true
    
    # Producers
    for pid_file in "${PIDS_DIR}"/producer-*.pid; do
        [[ -f "$pid_file" ]] || continue
        local name=$(basename "$pid_file" .pid)
        local pid=$(cat "$pid_file")
        local status="STOPPED"
        local start_time=""
        
        if kill -0 "$pid" 2>/dev/null; then
            status="RUNNING"
            start_time=$(ps -p "$pid" -o lstart= 2>/dev/null | xargs)
        fi
        
        [[ "$first" == true ]] || result+=","
        result+=$(json_object \
            "name" "$name" \
            "type" "producer" \
            "pid" "$pid" \
            "status" "$status" \
            "start_time" "$start_time" \
            "events_processed" "0")
        first=false
    done
    
    # Workers
    for pid_file in "${PIDS_DIR}"/worker-*.pid; do
        [[ -f "$pid_file" ]] || continue
        local name=$(basename "$pid_file" .pid)
        local pid=$(cat "$pid_file")
        local status="STOPPED"
        local start_time=""
        
        if kill -0 "$pid" 2>/dev/null; then
            status="RUNNING"
            start_time=$(ps -p "$pid" -o lstart= 2>/dev/null | xargs)
        fi
        
        [[ "$first" == true ]] || result+=","
        result+=$(json_object \
            "name" "$name" \
            "type" "worker" \
            "pid" "$pid" \
            "status" "$status" \
            "start_time" "$start_time" \
            "events_processed" "0")
        first=false
    done
    
    result+="]"
    echo "$result"
}

# Main manager loop
manager_run() {
    log_process "manager" "RUN" "$$" "Process manager running"
    
    # Start default processes
    for i in $(seq 1 "$DEFAULT_PRODUCERS"); do
        start_producer "producer-$i"
    done
    
    for i in $(seq 1 "$DEFAULT_WORKERS"); do
        start_worker "worker-$i"
    done
    
    # Monitor loop
    while true; do
        monitor_processes
        stats_update_uptime
        stats_update_pending
        sleep "$MANAGER_POLL_INTERVAL"
    done
}

# =============================================================================
# COMMAND INTERFACE
# =============================================================================

handle_command() {
    local cmd="$1"
    shift
    
    case "$cmd" in
        start)
            local type="${1:-all}"
            case "$type" in
                producer) start_producer "${2:-}" ;;
                worker) start_worker "${2:-}" ;;
                all)
                    for i in $(seq 1 "$DEFAULT_PRODUCERS"); do start_producer "producer-$i"; done
                    for i in $(seq 1 "$DEFAULT_WORKERS"); do start_worker "worker-$i"; done
                    ;;
            esac
            ;;
        stop)
            local type="${1:-all}"
            case "$type" in
                producer) stop_producer "${2:-}" ;;
                worker) stop_worker "${2:-}" ;;
                all) stop_all_producers; stop_all_workers ;;
            esac
            ;;
        list)
            list_all_processes
            ;;
        status)
            get_process_status
            ;;
        restart)
            local name="$1"
            local pid=$(load_pid "$name")
            if [[ -n "$pid" ]]; then
                kill_graceful "$pid" 5
                remove_pid "$name"
            fi
            if [[ "$name" == producer-* ]]; then
                start_producer "$name"
            elif [[ "$name" == worker-* ]]; then
                start_worker "$name"
            fi
            ;;
        *)
            echo "Unknown command: $cmd"
            return 1
            ;;
    esac
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    manager_init
    
    if [[ $# -gt 0 ]]; then
        handle_command "$@"
    else
        manager_run
    fi
}

main "$@"
#!/usr/bin/env bash
# System Cleanup
# Graceful shutdown and resource cleanup

# Prevent multiple sourcing
[[ -n "${CLEANUP_LOADED:-}" ]] && return 0
readonly CLEANUP_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/../../config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../ipc/fifo.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../synchronization/locks.sh"

# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

# Cleanup all runtime resources
cleanup_all() {
    log_system "Starting system cleanup..."
    
    # Stop all processes
    cleanup_processes
    
    # Remove FIFOs
    fifo_remove_all
    
    # Remove locks
    lock_cleanup_all
    
    # Remove PID files
    cleanup_pids
    
    # Rotate logs if needed
    rotate_logs 10000
    
    log_system "System cleanup completed"
}

# Stop all tracked processes
cleanup_processes() {
    log_system "Stopping all tracked processes..."
    
    # Get all PIDs
    local pids=()
    for pid_file in "${PIDS_DIR}"/*.pid; do
        [[ -f "$pid_file" ]] || continue
        local pid=$(cat "$pid_file")
        [[ -n "$pid" ]] && pids+=("$pid")
    done
    
    # Send TERM signal
    for pid in "${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null
        fi
    done
    
    # Wait for graceful shutdown
    sleep 2
    
    # Force kill remaining
    for pid in "${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -KILL "$pid" 2>/dev/null
            log_warn "Force killed process: $pid"
        fi
    done
}

# Cleanup PID files
cleanup_pids() {
    log_system "Cleaning up PID files..."
    rm -f "${PIDS_DIR}"/*.pid
}

# Cleanup old log files
cleanup_old_logs() {
    local days="${1:-7}"
    log_system "Cleaning up logs older than $days days..."
    
    find "$LOGS_DIR" -name "*.log" -mtime "+$days" -delete 2>/dev/null
    find "$LOGS_DIR" -name "*.log.*" -mtime "+$days" -delete 2>/dev/null
}

# Cleanup old events
cleanup_old_events() {
    local days="${1:-30}"
    log_system "Cleaning up events older than $days days..."
    
    find "$EVENTS_DIR" -name "*.json" -mtime "+$days" -delete 2>/dev/null
}

# Cleanup old posts
cleanup_old_posts() {
    local days="${1:-90}"
    log_system "Cleaning up posts older than $days days..."
    
    find "$POSTS_DIR" -name "*.json" -mtime "+$days" -delete 2>/dev/null
}

# Cleanup queue
cleanup_queue() {
    log_system "Cleaning up queue..."
    queue_clear
    pqueue_clear
}

# Emergency cleanup (force)
cleanup_emergency() {
    log_warn "EMERGENCY CLEANUP INITIATED"
    
    # Kill all our processes immediately
    pkill -f "backend/processes/" 2>/dev/null
    pkill -f "backend/system/resource_monitor" 2>/dev/null
    
    # Remove all runtime files
    rm -rf "${RUNTIME_DIR:?}/"*
    mkdir -p "$PIDS_DIR" "$LOCKS_DIR" "$PIPES_DIR"
    
    log_warn "Emergency cleanup completed"
}

# Pre-startup cleanup (clean previous run)
cleanup_prestart() {
    log_system "Pre-startup cleanup..."
    
    # Remove stale PID files
    for pid_file in "${PIDS_DIR}"/*.pid; do
        [[ -f "$pid_file" ]] || continue
        local pid=$(cat "$pid_file")
        if ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$pid_file"
        else
            # Process still running, kill it
            kill -TERM "$pid" 2>/dev/null
            sleep 1
            kill -KILL "$pid" 2>/dev/null
            rm -f "$pid_file"
        fi
    done
    
    # Remove stale FIFOs
    fifo_remove_all
    
    # Remove stale locks
    lock_cleanup_all
    
    log_system "Pre-startup cleanup completed"
}

# Save state before shutdown
save_state() {
    log_system "Saving system state..."
    
    # Save statistics
    stats_get_all > "${STATS_DIR}/state_stats.json"
    
    # Save queue
    queue_get_all > "${QUEUE_DIR}/state_queue.json"
    pqueue_get_all > "${QUEUE_DIR}/state_priority_queue.json"
    
    # Save feed
    feed_get_all > "${FEED_DIR}/state_feed.json"
    
    # Save process list
    list_pids > "${PIDS_DIR}/state_pids.txt"
    
    log_system "System state saved"
}

# Restore state after startup
restore_state() {
    log_system "Restoring system state..."
    
    # Restore queue if exists
    if [[ -f "${QUEUE_DIR}/state_queue.json" ]]; then
        cp "${QUEUE_DIR}/state_queue.json" "$QUEUE_FILE"
        log_system "Queue restored"
    fi
    
    if [[ -f "${QUEUE_DIR}/state_priority_queue.json" ]]; then
        cp "${QUEUE_DIR}/state_priority_queue.json" "$PRIORITY_QUEUE_FILE"
        log_system "Priority queue restored"
    fi
    
    # Feed is already persistent in files
    log_system "Feed already persistent"
    
    log_system "System state restored"
}

# Export functions
export -f cleanup_all cleanup_processes cleanup_pids cleanup_old_logs
export -f cleanup_old_events cleanup_old_posts cleanup_queue cleanup_emergency
export -f cleanup_prestart save_state restore_state
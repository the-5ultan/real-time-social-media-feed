#!/usr/bin/env bash
# Synchronization using flock
# Provides mutual exclusion for critical sections

# Prevent multiple sourcing
[[ -n "${LOCKS_LOADED:-}" ]] && return 0
readonly LOCKS_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/../../config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/logger.sh"

# =============================================================================
# LOCK MANAGEMENT
# =============================================================================

# Ensure locks directory exists
mkdir -p "$LOCKS_DIR"

# Acquire exclusive lock
# Usage: lock_acquire "lock_name" [timeout]
lock_acquire() {
    local lock_name="$1"
    local timeout="${2:-10}"
    local lock_file="${LOCKS_DIR}/${lock_name}.lock"
    
    # Create lock file if not exists
    touch "$lock_file"
    
    local fd=200
    local count=0
    
    # Try to acquire lock with timeout
    while ! flock -x -n "$fd" 2>/dev/null; do
        if [[ $count -ge $timeout ]]; then
            log_sync "$lock_name" "TIMEOUT" "$$" "Lock acquisition timeout after ${timeout}s"
            return 1
        fi
        sleep 1
        ((count++))
    done
    
    log_sync "$lock_name" "ACQUIRE" "$$" "Lock acquired"
    return 0
}

# Release lock
lock_release() {
    local lock_name="$1"
    local fd=200
    
    flock -u "$fd" 2>/dev/null
    log_sync "$lock_name" "RELEASE" "$$" "Lock released"
}

# Execute command with lock
# Usage: with_lock "lock_name" command [args...]
with_lock() {
    local lock_name="$1"
    shift
    local lock_file="${LOCKS_DIR}/${lock_name}.lock"
    
    touch "$lock_file"
    
    (
        flock -x 200
        log_sync "$lock_name" "ACQUIRE" "$$" "Lock acquired for command: $*"
        "$@"
        local result=$?
        log_sync "$lock_name" "RELEASE" "$$" "Lock released after command"
        return $result
    ) 200>"$lock_file"
}

# Try lock (non-blocking)
# Returns 0 if acquired, 1 if not available
lock_try() {
    local lock_name="$1"
    local lock_file="${LOCKS_DIR}/${lock_name}.lock"
    
    touch "$lock_file"
    
    if flock -x -n 200 2>/dev/null; then
        log_sync "$lock_name" "TRY_ACQUIRE" "$$" "Lock acquired (non-blocking)"
        return 0
    else
        log_sync "$lock_name" "TRY_FAILED" "$$" "Lock not available (non-blocking)"
        return 1
    fi
} 200>"${LOCKS_DIR}/${lock_name}.lock"

# Check if lock is held
lock_is_held() {
    local lock_name="$1"
    local lock_file="${LOCKS_DIR}/${lock_name}.lock"
    
    # Try to acquire non-blocking, if fails, lock is held
    if flock -x -n 200 2>/dev/null; then
        flock -u 200
        return 1  # Not held
    else
        return 0  # Held
    fi
} 200>"$lock_file"

# Get lock info
lock_info() {
    local lock_name="$1"
    local lock_file="${LOCKS_DIR}/${lock_name}.lock"
    
    if [[ -f "$lock_file" ]]; then
        local held="false"
        lock_is_held "$lock_name" && held="true"
        
        json_object \
            "name" "$lock_name" \
            "file" "$lock_file" \
            "held" "$held"
    else
        json_object "name" "$lock_name" "file" "$lock_file" "held" "false" "exists" "false"
    fi
}

# List all locks
lock_list() {
    local result="["
    local first=true
    
    for lock_file in "${LOCKS_DIR}"/*.lock; do
        [[ -f "$lock_file" ]] || continue
        local name=$(basename "$lock_file" .lock)
        local info=$(lock_info "$name")
        
        [[ "$first" == true ]] || result+=","
        result+="$info"
        first=false
    done
    
    result+="]"
    echo "$result"
}

# Force release lock (emergency)
lock_force_release() {
    local lock_name="$1"
    local lock_file="${LOCKS_DIR}/${lock_name}.lock"
    
    # Remove lock file
    rm -f "$lock_file"
    log_warn "SYNC" "Force released lock: $lock_name"
}

# Cleanup all locks
lock_cleanup_all() {
    rm -f "${LOCKS_DIR}"/*.lock
    log_sync "cleanup" "ALL" "$$" "All locks cleaned up"
}

# =============================================================================
# PREDEFINED LOCKS
# =============================================================================

# Feed lock
feed_lock() { with_lock "feed" "$@"; }
feed_lock_acquire() { lock_acquire "feed" "$@"; }
feed_lock_release() { lock_release "feed"; }

# Queue lock
queue_lock() { with_lock "queue" "$@"; }
queue_lock_acquire() { lock_acquire "queue" "$@"; }
queue_lock_release() { lock_release "queue"; }

# Stats lock
stats_lock() { with_lock "stats" "$@"; }
stats_lock_acquire() { lock_acquire "stats" "$@"; }
stats_lock_release() { lock_release "stats"; }

# Users lock
users_lock() { with_lock "users" "$@"; }
users_lock_acquire() { lock_acquire "users" "$@"; }
users_lock_release() { lock_release "users"; }

# =============================================================================
# CRITICAL SECTION HELPERS
# =============================================================================

# Execute in feed critical section
feed_critical() {
    feed_lock "$@"
}

# Execute in queue critical section
queue_critical() {
    queue_lock "$@"
}

# Execute in stats critical section
stats_critical() {
    stats_lock "$@"
}

# Execute in users critical section
users_critical() {
    users_lock "$@"
}

# Export functions
export -f lock_acquire lock_release with_lock lock_try lock_is_held lock_info lock_list lock_force_release lock_cleanup_all
export -f feed_lock feed_lock_acquire feed_lock_release
export -f queue_lock queue_lock_acquire queue_lock_release
export -f stats_lock stats_lock_acquire stats_lock_release
export -f users_lock users_lock_acquire users_lock_release
export -f feed_critical queue_critical stats_critical users_critical
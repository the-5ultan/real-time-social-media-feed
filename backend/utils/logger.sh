#!/usr/bin/env bash
# Logger for Real-Time Social Media Feed
# Provides structured logging with timestamps, PIDs, and categories

# Prevent multiple sourcing
[[ -n "${LOGGER_LOADED:-}" ]] && return 0
readonly LOGGER_LOADED=1

# Source dependencies
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# =============================================================================
# LOG LEVELS
# =============================================================================

# Log levels (lower = more verbose)
readonly LOG_LVL_DEBUG=0
readonly LOG_LVL_INFO=1
readonly LOG_LVL_WARN=2
readonly LOG_LVL_ERROR=3

# Current log level (can be overridden by LOG_LEVEL env var)
CURRENT_LOG_LEVEL="${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}"

# =============================================================================
# LOG FILES
# =============================================================================

# Ensure log directory exists
mkdir -p "$LOGS_DIR"

# =============================================================================
# CORE LOGGING FUNCTION
# =============================================================================

# Internal log function
_log() {
    local level="$1"
    local category="$2"
    local message="$3"
    local pid="${4:-$$}"
    local user="${5:-system}"
    local event_id="${6:-}"
    local event_type="${7:-}"
    local status="${8:-}"
    
    # Check log level
    [[ $level -ge $CURRENT_LOG_LEVEL ]] || return 0
    
    local timestamp=$(get_timestamp)
    local level_str=""
    local color=""
    
    case $level in
        $LOG_LVL_DEBUG) level_str="DEBUG"; color="$COLOR_MAGENTA" ;;
        $LOG_LVL_INFO)  level_str="INFO";  color="$COLOR_BLUE" ;;
        $LOG_LVL_WARN)  level_str="WARN";  color="$COLOR_YELLOW" ;;
        $LOG_LVL_ERROR) level_str="ERROR"; color="$COLOR_RED" ;;
    esac
    
    # Build log line
    local log_line="[$timestamp] PID=$pid USER=$user CATEGORY=$category LEVEL=$level_str"
    
    [[ -n "$event_id" ]] && log_line+=" EVENT_ID=$event_id"
    [[ -n "$event_type" ]] && log_line+=" EVENT_TYPE=$event_type"
    [[ -n "$status" ]] && log_line+=" STATUS=$status"
    log_line+=" MSG=\"$message\""
    
    # Write to appropriate log file
    case $category in
        EVENT)
            echo "$log_line" >> "$EVENTS_LOG"
            ;;
        WORKER)
            echo "$log_line" >> "$WORKERS_LOG"
            ;;
        SYSTEM|*)
            echo "$log_line" >> "$SYSTEM_LOG"
            ;;
    esac
    
    # Also output to console with colors (for debugging)
    if [[ -t 1 ]] || [[ -n "${LOG_TO_CONSOLE:-}" ]]; then
        echo "${color}[$level_str]${COLOR_RESET} [$category] $message"
    fi
}

# =============================================================================
# PUBLIC LOGGING FUNCTIONS
# =============================================================================

# Log debug message
log_debug() {
    local category="$1"
    local message="$2"
    _log $LOG_LVL_DEBUG "$category" "$message" "$$" "system" "" "" ""
}

# Log info message
log_info() {
    local category="$1"
    local message="$2"
    _log $LOG_LVL_INFO "$category" "$message" "$$" "system" "" "" ""
}

# Log warning
log_warn() {
    local category="$1"
    local message="$2"
    _log $LOG_LVL_WARN "$category" "$message" "$$" "system" "" "" ""
}

# Log error
log_error() {
    local category="$1"
    local message="$2"
    _log $LOG_LVL_ERROR "$category" "$message" "$$" "system" "" "" ""
}

# Log event (for events.log)
log_event() {
    local event_id="$1"
    local user="$2"
    local event_type="$3"
    local status="$4"
    local message="$5"
    local pid="${6:-$$}"
    
    _log $LOG_LVL_INFO "EVENT" "$message" "$pid" "$user" "$event_id" "$event_type" "$status"
}

# Log worker activity (for workers.log)
log_worker() {
    local worker_id="$1"
    local event_id="$2"
    local event_type="$3"
    local status="$4"
    local message="$5"
    local pid="${6:-$$}"
    
    _log $LOG_LVL_INFO "WORKER" "$message" "$pid" "$worker_id" "$event_id" "$event_type" "$status"
}

# Log system event (for system.log)
log_system() {
    local message="$1"
    local level="${2:-INFO}"
    local pid="${3:-$$}"
    
    local lvl_num=$LOG_LVL_INFO
    case "$level" in
        DEBUG) lvl_num=$LOG_LVL_DEBUG ;;
        WARN)  lvl_num=$LOG_LVL_WARN ;;
        ERROR) lvl_num=$LOG_LVL_ERROR ;;
    esac
    
    _log $lvl_num "SYSTEM" "$message" "$pid" "system" "" "" ""
}

# =============================================================================
# SPECIALIZED LOGGING
# =============================================================================

# Log producer activity
log_producer() {
    local producer_id="$1"
    local event_id="$2"
    local event_type="$3"
    local message="$4"
    local pid="${5:-$$}"
    
    _log $LOG_LVL_INFO "PRODUCER" "$message" "$pid" "$producer_id" "$event_id" "$event_type" "CREATED"
}

# Log queue operations
log_queue() {
    local operation="$1"
    local event_id="$2"
    local queue_size="$3"
    local message="$4"
    local pid="${5:-$$}"
    
    _log $LOG_LVL_INFO "QUEUE" "$message" "$pid" "queue" "$event_id" "$operation" "QUEUE_SIZE=$queue_size"
}

# Log feed operations
log_feed() {
    local operation="$1"
    local post_id="$2"
    local message="$3"
    local pid="${4:-$$}"
    
    _log $LOG_LVL_INFO "FEED" "$message" "$pid" "feed" "$post_id" "$operation" ""
}

# Log synchronization events
log_sync() {
    local lock_name="$1"
    local action="$2"  # ACQUIRE, RELEASE, WAIT, TIMEOUT
    local pid="${3:-$$}"
    local message="$4"
    
    _log $LOG_LVL_DEBUG "SYNC" "$message" "$pid" "sync" "" "" "LOCK=$lock_name ACTION=$action"
}

# Log process lifecycle
log_process() {
    local process_name="$1"
    local action="$2"  # START, STOP, RESTART, CRASH
    local pid="${3:-$$}"
    local message="$4"
    
    _log $LOG_LVL_INFO "PROCESS" "$message" "$pid" "$process_name" "" "" "ACTION=$action"
}

# =============================================================================
# LOG MANAGEMENT
# =============================================================================

# Set log level
set_log_level() {
    local level="$1"
    case "$level" in
        DEBUG) CURRENT_LOG_LEVEL=$LOG_LVL_DEBUG ;;
        INFO)  CURRENT_LOG_LEVEL=$LOG_LVL_INFO ;;
        WARN)  CURRENT_LOG_LEVEL=$LOG_LVL_WARN ;;
        ERROR) CURRENT_LOG_LEVEL=$LOG_LVL_ERROR ;;
        *)     echo "Invalid log level: $level" >&2; return 1 ;;
    esac
    export CURRENT_LOG_LEVEL
}

# Get current log level name
get_log_level_name() {
    case $CURRENT_LOG_LEVEL in
        $LOG_LVL_DEBUG) echo "DEBUG" ;;
        $LOG_LVL_INFO)  echo "INFO" ;;
        $LOG_LVL_WARN)  echo "WARN" ;;
        $LOG_LVL_ERROR) echo "ERROR" ;;
        *)              echo "UNKNOWN" ;;
    esac
}

# Rotate logs (keep last N lines)
rotate_logs() {
    local max_lines="${1:-10000}"
    
    for log_file in "$EVENTS_LOG" "$WORKERS_LOG" "$SYSTEM_LOG"; do
        if [[ -f "$log_file" ]]; then
            local line_count=$(wc -l < "$log_file")
            if [[ $line_count -gt $max_lines ]]; then
                tail -n "$max_lines" "$log_file" > "${log_file}.tmp"
                mv "${log_file}.tmp" "$log_file"
                log_system "Rotated log file: $log_file (was $line_count lines)"
            fi
        fi
    done
}

# Clear all logs
clear_logs() {
    > "$EVENTS_LOG"
    > "$WORKERS_LOG"
    > "$SYSTEM_LOG"
    log_system "Logs cleared"
}

# Show recent logs
show_logs() {
    local category="${1:-SYSTEM}"
    local lines="${2:-50}"
    
    case "$category" in
        EVENT|EVENTS)
            tail -n "$lines" "$EVENTS_LOG" 2>/dev/null || echo "No events log found"
            ;;
        WORKER|WORKERS)
            tail -n "$lines" "$WORKERS_LOG" 2>/dev/null || echo "No workers log found"
            ;;
        SYSTEM|*)
            tail -n "$lines" "$SYSTEM_LOG" 2>/dev/null || echo "No system log found"
            ;;
    esac
}

# Export log functions
export -f log_debug log_info log_warn log_error
export -f log_event log_worker log_system
export -f log_producer log_queue log_feed log_sync log_process
export -f set_log_level get_log_level_name rotate_logs clear_logs show_logs
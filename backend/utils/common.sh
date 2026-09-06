#!/usr/bin/env bash
# Common utility functions for the Real-Time Social Media Feed
# Provides shared functionality across all backend scripts

# Prevent multiple sourcing
[[ -n "${COMMON_LOADED:-}" ]] && return 0
readonly COMMON_LOADED=1

# Source configuration
source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"

# =============================================================================
# JSON UTILITIES
# =============================================================================

# Escape string for JSON
json_escape() {
    local input="$1"
    input="${input//\\/\\\\}"
    input="${input//\"/\\\"}"
    input="${input//$'\n'/\\n}"
    input="${input//$'\r'/\\r}"
    input="${input//$'\t'/\\t}"
    echo "$input"
}

# Create JSON object from key-value pairs
json_object() {
    local result="{"
    local first=true
    
    while [[ $# -gt 0 ]]; do
        local key="$1"
        local value="$2"
        shift 2
        
        [[ "$first" == true ]] || result+=","
        result+="\"$(json_escape "$key")\":\"$(json_escape "$value")\""
        first=false
    done
    
    result+="}"
    echo "$result"
}

# Create JSON array from values
json_array() {
    local result="["
    local first=true
    
    for value in "$@"; do
        [[ "$first" == true ]] || result+=","
        result+="\"$(json_escape "$value")\""
        first=false
    done
    
    result+="]"
    echo "$result"
}

# Extract value from JSON (simple grep-based, for flat objects)
json_get() {
    local json="$1"
    local key="$2"
    echo "$json" | grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed 's/.*"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'
}

# Extract numeric value from JSON
json_get_num() {
    local json="$1"
    local key="$2"
    echo "$json" | grep -o "\"${key}\"[[:space:]]*:[[:space:]]*[0-9-]*" | sed 's/.*:[[:space:]]*\([0-9-]*\).*/\1/'
}

# =============================================================================
# ID GENERATION
# =============================================================================

# Generate unique ID (timestamp + random)
generate_id() {
    local prefix="${1:-}"
    local timestamp=$(date +%s%3N)
    local random=$((RANDOM % 10000))
    printf "%s%s%04d" "$prefix" "$timestamp" "$random"
}

# Generate event ID
generate_event_id() {
    generate_id "evt_"
}

# Generate post ID
generate_post_id() {
    generate_id "post_"
}

# Generate user ID
generate_user_id() {
    generate_id "user_"
}

# =============================================================================
# TIMESTAMP UTILITIES
# =============================================================================

# Get current timestamp in ISO format
get_timestamp() {
    date +"${LOG_TIMESTAMP_FORMAT}"
}

# Get current epoch milliseconds
get_epoch_ms() {
    date +%s%3N
}

# Get current epoch seconds
get_epoch_sec() {
    date +%s
}

# =============================================================================
# FILE OPERATIONS
# =============================================================================

# Atomic write to file (write to temp then move)
atomic_write() {
    local file="$1"
    local content="$2"
    local temp_file="${file}.tmp.$$"
    
    echo "$content" > "$temp_file"
    mv "$temp_file" "$file"
}

# Read file content safely
read_file() {
    local file="$1"
    [[ -f "$file" ]] && cat "$file" || echo ""
}

# Append to file with locking
append_file_locked() {
    local file="$1"
    local content="$2"
    local lock_file="${3:-${file}.lock}"
    
    (
        flock -x 200
        echo "$content" >> "$file"
    ) 200>"$lock_file"
}

# =============================================================================
# PROCESS UTILITIES
# =============================================================================

# Check if process is running
is_process_running() {
    local pid="$1"
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

# Get process info
get_process_info() {
    local pid="$1"
    if is_process_running "$pid"; then
        ps -p "$pid" -o pid,ppid,cmd,etime,pcpu,pmem --no-headers 2>/dev/null
    else
        echo ""
    fi
}

# Kill process gracefully
kill_graceful() {
    local pid="$1"
    local timeout="${2:-5}"
    
    if is_process_running "$pid"; then
        kill -TERM "$pid" 2>/dev/null
        local count=0
        while is_process_running "$pid" && [[ $count -lt $timeout ]]; do
            sleep 1
            ((count++))
        done
        if is_process_running "$pid"; then
            kill -KILL "$pid" 2>/dev/null
            return 1
        fi
        return 0
    fi
    return 0
}

# Save PID to file
save_pid() {
    local name="$1"
    local pid="$2"
    echo "$pid" > "${PIDS_DIR}/${name}.pid"
}

# Load PID from file
load_pid() {
    local name="$1"
    local pid_file="${PIDS_DIR}/${name}.pid"
    [[ -f "$pid_file" ]] && cat "$pid_file" || echo ""
}

# Remove PID file
remove_pid() {
    local name="$1"
    rm -f "${PIDS_DIR}/${name}.pid"
}

# List all saved PIDs
list_pids() {
    for pid_file in "${PIDS_DIR}"/*.pid; do
        [[ -f "$pid_file" ]] || continue
        local name=$(basename "$pid_file" .pid)
        local pid=$(cat "$pid_file")
        local status="STOPPED"
        is_process_running "$pid" && status="RUNNING"
        echo "${name}:${pid}:${status}"
    done
}

# Clean dead PID files
clean_dead_pids() {
    for pid_file in "${PIDS_DIR}"/*.pid; do
        [[ -f "$pid_file" ]] || continue
        local pid=$(cat "$pid_file")
        if ! is_process_running "$pid"; then
            rm -f "$pid_file"
        fi
    done
}

# =============================================================================
# VALIDATION UTILITIES
# =============================================================================

# Validate non-empty string
validate_not_empty() {
    local value="$1"
    local name="$2"
    [[ -n "$value" ]] || { echo "ERROR: $name cannot be empty" >&2; return 1; }
}

# Validate positive integer
validate_positive_int() {
    local value="$1"
    local name="$2"
    [[ "$value" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: $name must be a positive integer" >&2; return 1; }
}

# Validate non-negative integer
validate_non_negative_int() {
    local value="$1"
    local name="$2"
    [[ "$value" =~ ^[0-9]+$ ]] || { echo "ERROR: $name must be a non-negative integer" >&2; return 1; }
}

# Validate event type
validate_event_type() {
    local type="$1"
    case "$type" in
        "$EVENT_POST"|"$EVENT_LIKE"|"$EVENT_COMMENT"|"$EVENT_SHARE"|"$EVENT_FOLLOW"|"$EVENT_NOTIFICATION")
            return 0
            ;;
        *)
            echo "ERROR: Invalid event type: $type" >&2
            return 1
            ;;
    esac
}

# Validate priority
validate_priority() {
    local priority="$1"
    [[ "$priority" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: Priority must be positive integer" >&2; return 1; }
}

# =============================================================================
# COLOR OUTPUT
# =============================================================================

# Colors (only if terminal supports it)
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ $(tput colors) -ge 8 ]]; then
    readonly COLOR_RED=$(tput setaf 1)
    readonly COLOR_GREEN=$(tput setaf 2)
    readonly COLOR_YELLOW=$(tput setaf 3)
    readonly COLOR_BLUE=$(tput setaf 4)
    readonly COLOR_MAGENTA=$(tput setaf 5)
    readonly COLOR_CYAN=$(tput setaf 6)
    readonly COLOR_RESET=$(tput sgr0)
    readonly COLOR_BOLD=$(tput bold)
else
    readonly COLOR_RED=""
    readonly COLOR_GREEN=""
    readonly COLOR_YELLOW=""
    readonly COLOR_BLUE=""
    readonly COLOR_MAGENTA=""
    readonly COLOR_CYAN=""
    readonly COLOR_RESET=""
    readonly COLOR_BOLD=""
fi

print_info() {
    echo "${COLOR_BLUE}[INFO]${COLOR_RESET} $*"
}

print_success() {
    echo "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $*"
}

print_warn() {
    echo "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*"
}

print_error() {
    echo "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2
}

print_debug() {
    [[ ${DEFAULT_LOG_LEVEL} -le ${LOG_LEVEL_DEBUG} ]] && echo "${COLOR_MAGENTA}[DEBUG]${COLOR_RESET} $*"
}

# =============================================================================
# SIGNAL HANDLING
# =============================================================================

# Setup standard signal handlers
setup_signal_handlers() {
    local cleanup_func="${1:-cleanup}"
    
    trap "${cleanup_func}" EXIT
    trap "${cleanup_func}; exit 130" INT
    trap "${cleanup_func}; exit 143" TERM
}

# =============================================================================
# RETRY LOGIC
# =============================================================================

# Retry command with exponential backoff
retry() {
    local max_attempts="${1:-3}"
    local delay="${2:-1}"
    local cmd=("${@:3}")
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if "${cmd[@]}"; then
            return 0
        fi
        print_warn "Attempt $attempt failed, retrying in ${delay}s..."
        sleep "$delay"
        delay=$((delay * 2))
        ((attempt++))
    done
    
    print_error "Command failed after $max_attempts attempts"
    return 1
}

# =============================================================================
# VERSION INFO
# =============================================================================

# Get project version
get_version() {
    echo "1.0.0"
}

# Print banner
print_banner() {
    echo "${COLOR_CYAN}${COLOR_BOLD}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  Dynamic Data Structures: Real-Time Social Media Feed       ║"
    echo "║  Operating Systems University Project                        ║"
    echo "║  Version: $(get_version)                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo "${COLOR_RESET}"
}
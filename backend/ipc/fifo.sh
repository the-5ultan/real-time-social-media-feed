#!/usr/bin/env bash
# FIFO-based Inter-Process Communication
# Provides named pipe communication for producer-worker messaging

# Prevent multiple sourcing
[[ -n "${FIFO_IPC_LOADED:-}" ]] && return 0
readonly FIFO_IPC_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/../../config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/logger.sh"

# =============================================================================
# FIFO IPC
# =============================================================================

# Create all FIFOs
fifo_create_all() {
    mkdir -p "$PIPES_DIR"
    
    rm -f "$PRODUCER_FIFO" "$WORKER_FIFO" "$CONTROL_FIFO"
    
    mkfifo "$PRODUCER_FIFO" 2>/dev/null || true
    mkfifo "$WORKER_FIFO" 2>/dev/null || true
    mkfifo "$CONTROL_FIFO" 2>/dev/null || true
    
    log_sync "fifo" "CREATE" "$$" "FIFOs created: $PRODUCER_FIFO, $WORKER_FIFO, $CONTROL_FIFO"
}

# Remove all FIFOs
fifo_remove_all() {
    rm -f "$PRODUCER_FIFO" "$WORKER_FIFO" "$CONTROL_FIFO"
    log_sync "fifo" "REMOVE" "$$" "FIFOs removed"
}

# Create single FIFO
fifo_create() {
    local fifo_path="$1"
    mkdir -p "$(dirname "$fifo_path")"
    rm -f "$fifo_path"
    mkfifo "$fifo_path" 2>/dev/null || true
}

# Remove single FIFO
fifo_remove() {
    local fifo_path="$1"
    rm -f "$fifo_path"
}

# Check if FIFO exists
fifo_exists() {
    local fifo_path="$1"
    [[ -p "$fifo_path" ]]
}

# Write to FIFO (non-blocking with timeout)
fifo_write() {
    local fifo_path="$1"
    local message="$2"
    local timeout="${3:-5}"
    
    if ! fifo_exists "$fifo_path"; then
        log_error "IPC" "FIFO does not exist: $fifo_path"
        return 1
    fi
    
    # Use timeout to prevent indefinite blocking
    (
        echo "$message" > "$fifo_path"
    ) &
    local write_pid=$!
    
    local count=0
    while kill -0 "$write_pid" 2>/dev/null && [[ $count -lt $timeout ]]; do
        sleep 1
        ((count++))
    done
    
    if kill -0 "$write_pid" 2>/dev/null; then
        kill -KILL "$write_pid" 2>/dev/null
        log_warn "IPC" "FIFO write timeout: $fifo_path"
        return 1
    fi
    
    wait "$write_pid" 2>/dev/null
    return 0
}

# Read from FIFO (blocking)
fifo_read() {
    local fifo_path="$1"
    
    if ! fifo_exists "$fifo_path"; then
        log_error "IPC" "FIFO does not exist: $fifo_path"
        return 1
    fi
    
    # This blocks until data is available
    cat "$fifo_path"
}

# Read from FIFO with timeout
fifo_read_timeout() {
    local fifo_path="$1"
    local timeout="${2:-1}"
    
    if ! fifo_exists "$fifo_path"; then
        return 1
    fi
    
    # Use read with timeout
    local line
    if read -t "$timeout" line < "$fifo_path"; then
        echo "$line"
        return 0
    else
        return 1
    fi
}

# Send command to control FIFO
fifo_send_command() {
    local command="$1"
    local args="${2:-}"
    
    local message=$(json_object "command" "$command" "args" "$args" "timestamp" "$(get_timestamp)" "pid" "$$")
    fifo_write "$CONTROL_FIFO" "$message"
}

# Listen for commands on control FIFO
fifo_listen_commands() {
    local handler_func="$1"
    
    log_sync "control_fifo" "LISTEN" "$$" "Listening for commands"
    
    while true; do
        local line
        if line=$(fifo_read_timeout "$CONTROL_FIFO" 1); then
            local cmd=$(json_get "$line" "command")
            local args=$(json_get "$line" "args")
            $handler_func "$cmd" "$args"
        fi
    done
}

# Producer sends event to worker via FIFO
fifo_producer_send_event() {
    local event_json="$1"
    local message=$(json_object "type" "EVENT" "payload" "$event_json" "timestamp" "$(get_timestamp)")
    fifo_write "$PRODUCER_FIFO" "$message"
}

# Worker receives event from producer FIFO
fifo_worker_receive_event() {
    local timeout="${1:-1}"
    local line
    
    if line=$(fifo_read_timeout "$PRODUCER_FIFO" "$timeout"); then
        local type=$(json_get "$line" "type")
        if [[ "$type" == "EVENT" ]]; then
            json_get "$line" "payload"
            return 0
        fi
    fi
    return 1
}

# Worker sends result back
fifo_worker_send_result() {
    local event_id="$1"
    local status="$2"
    local result="${3:-}"
    
    local message=$(json_object \
        "type" "RESULT" \
        "event_id" "$event_id" \
        "status" "$status" \
        "result" "$result" \
        "timestamp" "$(get_timestamp)" \
        "worker_pid" "$$")
    
    fifo_write "$WORKER_FIFO" "$message"
}

# Producer receives result
fifo_producer_receive_result() {
    local timeout="${1:-1}"
    local line
    
    if line=$(fifo_read_timeout "$WORKER_FIFO" "$timeout"); then
        local type=$(json_get "$line" "type")
        if [[ "$type" == "RESULT" ]]; then
            echo "$line"
            return 0
        fi
    fi
    return 1
}

# Broadcast message to all workers (via control FIFO)
fifo_broadcast() {
    local message="$1"
    local msg_json=$(json_object "type" "BROADCAST" "payload" "$message" "timestamp" "$(get_timestamp)")
    fifo_write "$CONTROL_FIFO" "$msg_json"
}

# =============================================================================
# HIGH-LEVEL IPC INTERFACE
# =============================================================================

# Initialize IPC for producer
ipc_producer_init() {
    fifo_create_all
    log_sync "ipc" "PRODUCER_INIT" "$$" "Producer IPC initialized"
}

# Initialize IPC for worker
ipc_worker_init() {
    log_sync "ipc" "WORKER_INIT" "$$" "Worker IPC initialized"
}

# Initialize IPC for manager
ipc_manager_init() {
    fifo_create_all
    log_sync "ipc" "MANAGER_INIT" "$$" "Manager IPC initialized"
}

# Cleanup IPC
ipc_cleanup() {
    fifo_remove_all
    log_sync "ipc" "CLEANUP" "$$" "IPC cleaned up"
}

# Export functions
export -f fifo_create_all fifo_remove_all fifo_create fifo_remove fifo_exists
export -f fifo_write fifo_read fifo_read_timeout
export -f fifo_send_command fifo_listen_commands
export -f fifo_producer_send_event fifo_worker_receive_event
export -f fifo_worker_send_result fifo_producer_receive_result fifo_broadcast
export -f ipc_producer_init ipc_worker_init ipc_manager_init ipc_cleanup
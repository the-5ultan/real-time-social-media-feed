#!/usr/bin/env bash
# Dynamic Event Queue Data Structure
# Implements FIFO queue with enqueue, dequeue, peek, size operations
# Thread-safe using flock

# Prevent multiple sourcing
[[ -n "${QUEUE_DS_LOADED:-}" ]] && return 0
readonly QUEUE_DS_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/../../config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/validation.sh"

# =============================================================================
# QUEUE DATA STRUCTURE
# =============================================================================

# Queue stored as JSON array in QUEUE_FILE
# Front = index 0 (oldest), Rear = last index (newest)

# Initialize queue
queue_init() {
    local queue_file="${1:-$QUEUE_FILE}"
    [[ -f "$queue_file" ]] || atomic_write "$queue_file" "[]"
    log_queue "INIT" "" 0 "Queue initialized at $queue_file"
}

# Get queue size
queue_size() {
    local queue_file="${1:-$QUEUE_FILE}"
    local content=$(read_file "$queue_file")
    echo "$content" | jq 'length' 2>/dev/null || echo 0
}

# Check if queue is empty
queue_is_empty() {
    [[ $(queue_size "$1") -eq 0 ]]
}

# Check if queue is full
queue_is_full() {
    local queue_file="${1:-$QUEUE_FILE}"
    [[ $(queue_size "$queue_file") -ge $QUEUE_MAX_SIZE ]]
}

# Enqueue event (add to rear)
queue_enqueue() {
    local event_json="$1"
    local queue_file="${2:-$QUEUE_FILE}"
    
    validate_event_for_queue "$event_json" || return 1
    
    (
        flock -x 200
        
        if queue_is_full "$queue_file"; then
            log_queue "ENQUEUE_FAILED" "$(json_get "$event_json" "event_id")" "$(queue_size "$queue_file")" "Queue full, dropping event"
            return 1
        fi
        
        local content=$(read_file "$queue_file")
        local new_queue=$(echo "$content" | jq --argjson event "$event_json" '. + [$event]')
        atomic_write "$queue_file" "$new_queue"
        
        local event_id=$(json_get "$event_json" "event_id")
        local new_size=$(queue_size "$queue_file")
        log_queue "ENQUEUE" "$event_id" "$new_size" "Event enqueued"
    ) 200>"$QUEUE_LOCK"
}

# Dequeue event (remove from front)
queue_dequeue() {
    local queue_file="${1:-$QUEUE_FILE}"
    local event_json=""
    
    (
        flock -x 200
        local content=$(read_file "$queue_file")
        local size=$(queue_size "$queue_file")
        
        if [[ $size -eq 0 ]]; then
            log_queue "DEQUEUE_EMPTY" "" 0 "Queue empty"
            echo ""
            return 1
        fi
        
        event_json=$(echo "$content" | jq '.[0]')
        local new_queue=$(echo "$content" | jq '.[1:]')
        atomic_write "$queue_file" "$new_queue"
        
        local event_id=$(json_get "$event_json" "event_id")
        local new_size=$(queue_size "$queue_file")
        log_queue "DEQUEUE" "$event_id" "$new_size" "Event dequeued"
    ) 200>"$QUEUE_LOCK"
    
    echo "$event_json"
}

# Peek at front event (without removing)
queue_peek() {
    local queue_file="${1:-$QUEUE_FILE}"
    local content=$(read_file "$queue_file")
    local size=$(queue_size "$queue_file")
    
    if [[ $size -eq 0 ]]; then
        echo ""
        return 1
    fi
    
    echo "$content" | jq '.[0]'
}

# Peek at rear event
queue_peek_rear() {
    local queue_file="${1:-$QUEUE_FILE}"
    local content=$(read_file "$queue_file")
    local size=$(queue_size "$queue_file")
    
    if [[ $size -eq 0 ]]; then
        echo ""
        return 1
    fi
    
    echo "$content" | jq '.[-1]'
}

# Get all events (for debugging/monitoring)
queue_get_all() {
    local queue_file="${1:-$QUEUE_FILE}"
    local limit="${2:-0}"
    local content=$(read_file "$queue_file")
    
    if [[ $limit -gt 0 ]]; then
        echo "$content" | jq --argjson lim "$limit" '.[:$lim]'
    else
        echo "$content"
    fi
}

# Get events by type
queue_get_by_type() {
    local event_type="$1"
    local queue_file="${2:-$QUEUE_FILE}"
    local content=$(read_file "$queue_file")
    echo "$content" | jq --arg type "$event_type" 'map(select(.event_type == $type))'
}

# Get events by priority
queue_get_by_priority() {
    local priority="$1"
    local queue_file="${2:-$QUEUE_FILE}"
    local content=$(read_file "$queue_file")
    echo "$content" | jq --argjson pri "$priority" 'map(select(.priority == $pri))'
}

# Remove specific event by ID
queue_remove_event() {
    local event_id="$1"
    local queue_file="${2:-$QUEUE_FILE}"
    
    (
        flock -x 200
        local content=$(read_file "$queue_file")
        local new_queue=$(echo "$content" | jq --arg eid "$event_id" 'map(select(.event_id != $eid))')
        atomic_write "$queue_file" "$new_queue"
        log_queue "REMOVE" "$event_id" "$(queue_size "$queue_file")" "Event removed from queue"
    ) 200>"$QUEUE_LOCK"
}

# Clear queue
queue_clear() {
    local queue_file="${1:-$QUEUE_FILE}"
    
    (
        flock -x 200
        atomic_write "$queue_file" "[]"
        log_queue "CLEAR" "" 0 "Queue cleared"
    ) 200>"$QUEUE_LOCK"
}

# Get queue statistics
queue_get_stats() {
    local queue_file="${1:-$QUEUE_FILE}"
    local content=$(read_file "$queue_file")
    local size=$(queue_size "$queue_file")
    
    if [[ $size -eq 0 ]]; then
        json_object "size" "0" "by_type" "{}" "by_priority" "{}"
        return
    fi
    
    local by_type=$(echo "$content" | jq 'group_by(.event_type) | map({(.[0].event_type): length}) | add // {}')
    local by_priority=$(echo "$content" | jq 'group_by(.priority) | map({(.[0].priority | tostring): length}) | add // {}')
    
    json_object \
        "size" "$size" \
        "by_type" "$by_type" \
        "by_priority" "$by_priority"
}

# Export functions
export -f queue_init queue_size queue_is_empty queue_is_full
export -f queue_enqueue queue_dequeue queue_peek queue_peek_rear
export -f queue_get_all queue_get_by_type queue_get_by_priority
export -f queue_remove_event queue_clear queue_get_stats
#!/usr/bin/env bash
# Priority Queue Data Structure
# Implements priority-based queue (lower priority number = higher priority)
# Uses separate priority queues internally

# Prevent multiple sourcing
[[ -n "${PRIORITY_QUEUE_LOADED:-}" ]] && return 0
readonly PRIORITY_QUEUE_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/../../config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/queue.sh"

# =============================================================================
# PRIORITY QUEUE DATA STRUCTURE
# =============================================================================

# Priority queue uses multiple FIFO queues, one per priority level
# Stored as JSON object: {"1": [...], "2": [...], ...}

# Initialize priority queue
pqueue_init() {
    local pqueue_file="${1:-$PRIORITY_QUEUE_FILE}"
    [[ -f "$pqueue_file" ]] || atomic_write "$pqueue_file" "{}"
    log_queue "PQ_INIT" "" 0 "Priority queue initialized at $pqueue_file"
}

# Get total size across all priorities
pqueue_size() {
    local pqueue_file="${1:-$PRIORITY_QUEUE_FILE}"
    local content=$(read_file "$pqueue_file")
    echo "$content" | jq 'map(length) | add // 0' 2>/dev/null || echo 0
}

# Check if empty
pqueue_is_empty() {
    [[ $(pqueue_size "$1") -eq 0 ]]
}

# Enqueue with priority
pqueue_enqueue() {
    local event_json="$1"
    local pqueue_file="${2:-$PRIORITY_QUEUE_FILE}"
    
    validate_event_for_queue "$event_json" || return 1
    
    local priority=$(json_get_num "$event_json" "priority")
    [[ -n "$priority" ]] || priority=$PRIORITY_DEFAULT
    
    (
        flock -x 200
        local content=$(read_file "$pqueue_file")
        
        # Add to priority bucket
        local new_pqueue=$(echo "$content" | jq --argjson pri "$priority" --argjson event "$event_json" '
            .[$pri | tostring] = (.[$pri | tostring] // [] + [$event])
        ')
        atomic_write "$pqueue_file" "$new_pqueue"
        
        local event_id=$(json_get "$event_json" "event_id")
        log_queue "PQ_ENQUEUE" "$event_id" "$(pqueue_size "$pqueue_file")" "Event enqueued with priority $priority"
    ) 200>"$QUEUE_LOCK"
}

# Dequeue highest priority event
pqueue_dequeue() {
    local pqueue_file="${1:-$PRIORITY_QUEUE_FILE}"
    local event_json=""
    
    (
        flock -x 200
        local content=$(read_file "$pqueue_file")
        local size=$(pqueue_size "$pqueue_file")
        
        if [[ $size -eq 0 ]]; then
            log_queue "PQ_DEQUEUE_EMPTY" "" 0 "Priority queue empty"
            echo ""
            return 1
        fi
        
        # Find highest priority (lowest number) with events
        local priority=$(echo "$content" | jq -r 'keys_unsorted | map(tonumber) | sort | .[] | select(.[tostring] | length > 0) | tostring' | head -1)
        
        if [[ -z "$priority" || "$priority" == "null" ]]; then
            echo ""
            return 1
        fi
        
        # Get first event from that priority
        event_json=$(echo "$content" | jq --arg pri "$priority" '.[$pri][0]')
        
        # Remove it
        local new_pqueue=$(echo "$content" | jq --arg pri "$priority" '
            .[$pri] = .[$pri][1:] |
            if .[$pri] | length == 0 then del(.[$pri]) else . end
        ')
        atomic_write "$pqueue_file" "$new_pqueue"
        
        local event_id=$(json_get "$event_json" "event_id")
        log_queue "PQ_DEQUEUE" "$event_id" "$(pqueue_size "$pqueue_file")" "Event dequeued from priority $priority"
    ) 200>"$QUEUE_LOCK"
    
    echo "$event_json"
}

# Peek at highest priority event
pqueue_peek() {
    local pqueue_file="${1:-$PRIORITY_QUEUE_FILE}"
    local content=$(read_file "$pqueue_file")
    local size=$(pqueue_size "$pqueue_file")
    
    if [[ $size -eq 0 ]]; then
        echo ""
        return 1
    fi
    
    local priority=$(echo "$content" | jq -r 'keys_unsorted | map(tonumber) | sort | .[] | select(.[tostring] | length > 0) | tostring' | head -1)
    
    if [[ -z "$priority" || "$priority" == "null" ]]; then
        echo ""
        return 1
    fi
    
    echo "$content" | jq --arg pri "$priority" '.[$pri][0]'
}

# Get all events grouped by priority
pqueue_get_all() {
    local pqueue_file="${1:-$PRIORITY_QUEUE_FILE}"
    local content=$(read_file "$pqueue_file")
    echo "$content"
}

# Get size by priority
pqueue_size_by_priority() {
    local pqueue_file="${1:-$PRIORITY_QUEUE_FILE}"
    local content=$(read_file "$pqueue_file")
    echo "$content" | jq 'map_values(length)'
}

# Clear priority queue
pqueue_clear() {
    local pqueue_file="${1:-$PRIORITY_QUEUE_FILE}"
    
    (
        flock -x 200
        atomic_write "$pqueue_file" "{}"
        log_queue "PQ_CLEAR" "" 0 "Priority queue cleared"
    ) 200>"$QUEUE_LOCK"
}

# Get priority queue statistics
pqueue_get_stats() {
    local pqueue_file="${1:-$PRIORITY_QUEUE_FILE}"
    local content=$(read_file "$pqueue_file")
    local total=$(pqueue_size "$pqueue_file")
    local by_priority=$(pqueue_size_by_priority "$pqueue_file")
    local by_type="{}"
    
    if [[ $total -gt 0 ]]; then
        # Flatten and group by type
        by_type=$(echo "$content" | jq '
            [.[] | .[]] | 
            group_by(.event_type) | 
            map({(.[0].event_type): length}) | 
            add // {}
        ')
    fi
    
    json_object \
        "total_size" "$total" \
        "by_priority" "$by_priority" \
        "by_type" "$by_type"
}

# Export functions
export -f pqueue_init pqueue_size pqueue_is_empty
export -f pqueue_enqueue pqueue_dequeue pqueue_peek
export -f pqueue_get_all pqueue_size_by_priority pqueue_clear pqueue_get_stats
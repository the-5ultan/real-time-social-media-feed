#!/usr/bin/env bash
# Validation utilities for Real-Time Social Media Feed
# Provides input validation and data integrity checks

# Prevent multiple sourcing
[[ -n "${VALIDATION_LOADED:-}" ]] && return 0
readonly VALIDATION_LOADED=1

# Source dependencies
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"

# =============================================================================
# EVENT VALIDATION
# =============================================================================

# Validate event object (JSON string)
validate_event() {
    local event_json="$1"
    local errors=()
    
    # Required fields
    local event_id=$(json_get "$event_json" "event_id")
    local user_id=$(json_get "$event_json" "user_id")
    local event_type=$(json_get "$event_json" "event_type")
    local timestamp=$(json_get "$event_json" "timestamp")
    local priority=$(json_get_num "$event_json" "priority")
    
    [[ -n "$event_id" ]] || errors+=("Missing event_id")
    [[ -n "$user_id" ]] || errors+=("Missing user_id")
    [[ -n "$event_type" ]] || errors+=("Missing event_type")
    [[ -n "$timestamp" ]] || errors+=("Missing timestamp")
    [[ -n "$priority" ]] || errors+=("Missing priority")
    
    # Validate event type
    if [[ -n "$event_type" ]]; then
        case "$event_type" in
            "$EVENT_POST"|"$EVENT_LIKE"|"$EVENT_COMMENT"|"$EVENT_SHARE"|"$EVENT_FOLLOW"|"$EVENT_NOTIFICATION")
                ;;
            *) errors+=("Invalid event_type: $event_type") ;;
        esac
    fi
    
    # Validate priority
    if [[ -n "$priority" ]]; then
        [[ "$priority" =~ ^[1-9][0-9]*$ ]] || errors+=("Invalid priority: $priority")
    fi
    
    # Event-specific validation
    case "$event_type" in
        "$EVENT_POST")
            local content=$(json_get "$event_json" "content")
            [[ -n "$content" ]] || errors+=("POST event requires content")
            ;;
        "$EVENT_LIKE"|"$EVENT_SHARE")
            local target_post=$(json_get "$event_json" "target_post")
            [[ -n "$target_post" ]] || errors+=("$event_type event requires target_post")
            ;;
        "$EVENT_COMMENT")
            local target_post=$(json_get "$event_json" "target_post")
            local content=$(json_get "$event_json" "content")
            [[ -n "$target_post" ]] || errors+=("COMMENT event requires target_post")
            [[ -n "$content" ]] || errors+=("COMMENT event requires content")
            ;;
        "$EVENT_FOLLOW")
            local target_user=$(json_get "$event_json" "target_user")
            [[ -n "$target_user" ]] || errors+=("FOLLOW event requires target_user")
            ;;
    esac
    
    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    
    return 0
}

# Validate event for queue insertion
validate_event_for_queue() {
    local event_json="$1"
    validate_event "$event_json" || return 1
    
    # Additional queue-specific checks
    local status=$(json_get "$event_json" "status")
    [[ "$status" == "$STATUS_CREATED" || "$status" == "$STATUS_QUEUED" ]] || {
        echo "Event status must be CREATED or QUEUED for queue insertion"
        return 1
    }
    
    return 0
}

# =============================================================================
# USER VALIDATION
# =============================================================================

# Validate user object
validate_user() {
    local user_json="$1"
    local errors=()
    
    local user_id=$(json_get "$user_json" "user_id")
    local username=$(json_get "$user_json" "username")
    local created_at=$(json_get "$user_json" "created_at")
    
    [[ -n "$user_id" ]] || errors+=("Missing user_id")
    [[ -n "$username" ]] || errors+=("Missing username")
    [[ -n "$created_at" ]] || errors+=("Missing created_at")
    
    # Username format
    if [[ -n "$username" ]]; then
        [[ "$username" =~ ^[a-zA-Z0-9_]{3,30}$ ]] || errors+=("Invalid username format: $username")
    fi
    
    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    
    return 0
}

# Check if user exists
user_exists() {
    local user_id="$1"
    [[ -f "${USERS_DIR}/${user_id}.json" ]]
}

# Get user by ID
get_user() {
    local user_id="$1"
    local user_file="${USERS_DIR}/${user_id}.json"
    [[ -f "$user_file" ]] && cat "$user_file" || echo ""
}

# =============================================================================
# POST VALIDATION
# =============================================================================

# Validate post object
validate_post() {
    local post_json="$1"
    local errors=()
    
    local post_id=$(json_get "$post_json" "post_id")
    local user_id=$(json_get "$post_json" "user_id")
    local content=$(json_get "$post_json" "content")
    local timestamp=$(json_get "$post_json" "timestamp")
    
    [[ -n "$post_id" ]] || errors+=("Missing post_id")
    [[ -n "$user_id" ]] || errors+=("Missing user_id")
    [[ -n "$content" ]] || errors+=("Missing content")
    [[ -n "$timestamp" ]] || errors+=("Missing timestamp")
    
    # Validate user exists
    if [[ -n "$user_id" ]] && ! user_exists "$user_id"; then
        errors+=("User does not exist: $user_id")
    fi
    
    # Content length
    if [[ -n "$content" ]]; then
        [[ ${#content} -le 5000 ]] || errors+=("Content too long (max 5000 chars)")
    fi
    
    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    
    return 0
}

# Check if post exists
post_exists() {
    local post_id="$1"
    [[ -f "${POSTS_DIR}/${post_id}.json" ]]
}

# Get post by ID
get_post() {
    local post_id="$1"
    local post_file="${POSTS_DIR}/${post_id}.json"
    [[ -f "$post_file" ]] && cat "$post_file" || echo ""
}

# =============================================================================
# QUEUE VALIDATION
# =============================================================================

# Validate queue integrity
validate_queue() {
    local queue_file="${1:-$QUEUE_FILE}"
    local errors=()
    
    [[ -f "$queue_file" ]] || { echo "Queue file does not exist"; return 1; }
    
    local content=$(cat "$queue_file")
    [[ -n "$content" ]] || return 0  # Empty queue is valid
    
    # Basic JSON structure check
    echo "$content" | jq empty 2>/dev/null || errors+=("Invalid JSON structure")
    
    # Check each event in queue
    if command -v jq >/dev/null 2>&1; then
        local count=$(echo "$content" | jq 'length' 2>/dev/null || echo 0)
        for ((i=0; i<count; i++)); do
            local event=$(echo "$content" | jq ".[$i]" 2>/dev/null)
            if [[ -n "$event" ]]; then
                validate_event "$event" >/dev/null || errors+=("Invalid event at index $i")
            fi
        done
    fi
    
    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    
    return 0
}

# =============================================================================
# FEED VALIDATION
# =============================================================================

# Validate feed integrity
validate_feed() {
    local feed_file="${1:-$FEED_FILE}"
    local errors=()
    
    [[ -f "$feed_file" ]] || { echo "Feed file does not exist"; return 1; }
    
    local content=$(cat "$feed_file")
    [[ -n "$content" ]] || return 0  # Empty feed is valid
    
    # Basic JSON structure check
    echo "$content" | jq empty 2>/dev/null || errors+=("Invalid JSON structure")
    
    if command -v jq >/dev/null 2>&1; then
        local count=$(echo "$content" | jq 'length' 2>/dev/null || echo 0)
        for ((i=0; i<count; i++)); do
            local post=$(echo "$content" | jq ".[$i]" 2>/dev/null)
            if [[ -n "$post" ]]; then
                validate_post "$post" >/dev/null || errors+=("Invalid post at index $i")
            fi
        done
    fi
    
    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    
    return 0
}

# =============================================================================
# FILE SYSTEM VALIDATION
# =============================================================================

# Validate data directory structure
validate_data_structure() {
    local errors=()
    local required_dirs=(
        "$USERS_DIR"
        "$POSTS_DIR"
        "$EVENTS_DIR"
        "$FEED_DIR"
        "$QUEUE_DIR"
        "$STATS_DIR"
    )
    
    for dir in "${required_dirs[@]}"; do
        [[ -d "$dir" ]] || errors+=("Missing directory: $dir")
    done
    
    # Check runtime dirs
    local runtime_dirs=(
        "$PIDS_DIR"
        "$LOCKS_DIR"
        "$PIPES_DIR"
    )
    
    for dir in "${runtime_dirs[@]}"; do
        [[ -d "$dir" ]] || errors+=("Missing runtime directory: $dir")
    done
    
    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    
    return 0
}

# Validate all data files
validate_all_data() {
    local errors=()
    
    # Validate users
    for user_file in "$USERS_DIR"/*.json; do
        [[ -f "$user_file" ]] || continue
        validate_user "$(cat "$user_file")" >/dev/null || errors+=("Invalid user: $(basename "$user_file")")
    done
    
    # Validate posts
    for post_file in "$POSTS_DIR"/*.json; do
        [[ -f "$post_file" ]] || continue
        validate_post "$(cat "$post_file")" >/dev/null || errors+=("Invalid post: $(basename "$post_file")")
    done
    
    # Validate queue
    validate_queue >/dev/null || errors+=("Invalid queue")
    
    # Validate feed
    validate_feed >/dev/null || errors+=("Invalid feed")
    
    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    
    return 0
}

# =============================================================================
# SANITIZATION
# =============================================================================

# Sanitize string for safe use in file names
sanitize_filename() {
    local input="$1"
    echo "$input" | sed 's/[^a-zA-Z0-9._-]/_/g'
}

# Sanitize JSON string (remove control chars)
sanitize_json_string() {
    local input="$1"
    echo "$input" | sed 's/[\x00-\x1F\x7F]//g'
}

# =============================================================================
# EXPORT
# =============================================================================

export -f validate_event validate_event_for_queue
export -f validate_user user_exists get_user
export -f validate_post post_exists get_post
export -f validate_queue validate_feed validate_data_structure validate_all_data
export -f sanitize_filename sanitize_json_string
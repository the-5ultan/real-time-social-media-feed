#!/usr/bin/env bash
# Event Service
# Handles event creation, validation, persistence, and retrieval

# Prevent multiple sourcing
[[ -n "${EVENT_SERVICE_LOADED:-}" ]] && return 0
readonly EVENT_SERVICE_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/../../config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/validation.sh"

# =============================================================================
# EVENT SERVICE
# =============================================================================

# Create event from parameters
create_event() {
    local user_id="$1"
    local user_name="$2"
    local event_type="$3"
    local content="$4"
    local target_post="$5"
    local target_user="$6"
    local priority="$7"
    
    validate_not_empty "$user_id" "user_id" || return 1
    validate_not_empty "$user_name" "user_name" || return 1
    validate_event_type "$event_type" || return 1
    validate_priority "$priority" || priority=$PRIORITY_DEFAULT
    
    local event_id=$(generate_event_id)
    local timestamp=$(get_timestamp)
    local pid=$$
    
    local event_json=$(json_object \
        "event_id" "$event_id" \
        "user_id" "$user_id" \
        "user_name" "$user_name" \
        "event_type" "$event_type" \
        "content" "$content" \
        "target_post" "$target_post" \
        "target_user" "$target_user" \
        "priority" "$priority" \
        "timestamp" "$timestamp" \
        "status" "$STATUS_CREATED" \
        "pid" "$pid")
    
    # Persist event
    atomic_write "${EVENTS_DIR}/${event_id}.json" "$event_json"
    
    log_event "$event_id" "$user_name" "$event_type" "$STATUS_CREATED" "Event created" "$pid"
    
    echo "$event_json"
}

# Create POST event
create_post_event() {
    local user_id="$1"
    local user_name="$2"
    local content="$3"
    local priority="${4:-$PRIORITY_POST}"
    
    create_event "$user_id" "$user_name" "$EVENT_POST" "$content" "" "" "$priority"
}

# Create LIKE event
create_like_event() {
    local user_id="$1"
    local user_name="$2"
    local target_post="$3"
    local priority="${4:-$PRIORITY_LIKE}"
    
    create_event "$user_id" "$user_name" "$EVENT_LIKE" "" "$target_post" "" "$priority"
}

# Create COMMENT event
create_comment_event() {
    local user_id="$1"
    local user_name="$2"
    local target_post="$3"
    local content="$4"
    local priority="${5:-$PRIORITY_COMMENT}"
    
    create_event "$user_id" "$user_name" "$EVENT_COMMENT" "$content" "$target_post" "" "$priority"
}

# Create SHARE event
create_share_event() {
    local user_id="$1"
    local user_name="$2"
    local target_post="$3"
    local priority="${4:-$PRIORITY_SHARE}"
    
    create_event "$user_id" "$user_name" "$EVENT_SHARE" "" "$target_post" "" "$priority"
}

# Create FOLLOW event
create_follow_event() {
    local user_id="$1"
    local user_name="$2"
    local target_user="$3"
    local priority="${4:-$PRIORITY_FOLLOW}"
    
    create_event "$user_id" "$user_name" "$EVENT_FOLLOW" "" "" "$target_user" "$priority"
}

# Create NOTIFICATION event
create_notification_event() {
    local user_id="$1"
    local user_name="$2"
    local content="$3"
    local priority="${4:-$PRIORITY_NOTIFICATION}"
    
    create_event "$user_id" "$user_name" "$EVENT_NOTIFICATION" "$content" "" "" "$priority"
}

# Get event by ID
get_event() {
    local event_id="$1"
    local event_file="${EVENTS_DIR}/${event_id}.json"
    [[ -f "$event_file" ]] && cat "$event_file" || echo ""
}

# Update event status
update_event_status() {
    local event_id="$1"
    local status="$2"
    local event_file="${EVENTS_DIR}/${event_id}.json"
    
    if [[ -f "$event_file" ]]; then
        local event_json=$(cat "$event_file")
        local updated=$(echo "$event_json" | jq --arg s "$status" '.status = $s')
        atomic_write "$event_file" "$updated"
        log_event "$event_id" "$(json_get "$event_json" "user_name")" "$(json_get "$event_json" "event_type")" "$status" "Status updated"
    fi
}

# Queue event for processing
queue_event() {
    local event_json="$1"
    local use_priority="${2:-false}"
    
    local event_id=$(json_get "$event_json" "event_id")
    local event_type=$(json_get "$event_json" "event_type")
    local priority=$(json_get_num "$event_json" "priority")
    
    # Update status to QUEUED
    local queued_json=$(echo "$event_json" | jq --arg s "$STATUS_QUEUED" '.status = $s')
    atomic_write "${EVENTS_DIR}/${event_id}.json" "$queued_json"
    
    # Add to appropriate queue
    if [[ "$use_priority" == "true" ]]; then
        pqueue_enqueue "$queued_json"
    else
        queue_enqueue "$queued_json"
    fi
    
    log_event "$event_id" "$(json_get "$event_json" "user_name")" "$event_type" "$STATUS_QUEUED" "Event queued for processing"
}

# Process event (update feed, stats, etc.)
process_event() {
    local event_json="$1"
    local event_id=$(json_get "$event_json" "event_id")
    local event_type=$(json_get "$event_json" "event_type")
    local user_id=$(json_get "$event_json" "user_id")
    local user_name=$(json_get "$event_json" "user_name")
    local content=$(json_get "$event_json" "content")
    local target_post=$(json_get "$event_json" "target_post")
    local target_user=$(json_get "$event_json" "target_user")
    
    # Update status to PROCESSING
    update_event_status "$event_id" "$STATUS_PROCESSING"
    
    case "$event_type" in
        "$EVENT_POST")
            process_post_event "$event_json"
            ;;
        "$EVENT_LIKE")
            process_like_event "$event_json"
            ;;
        "$EVENT_COMMENT")
            process_comment_event "$event_json"
            ;;
        "$EVENT_SHARE")
            process_share_event "$event_json"
            ;;
        "$EVENT_FOLLOW")
            process_follow_event "$event_json"
            ;;
        "$EVENT_NOTIFICATION")
            process_notification_event "$event_json"
            ;;
    esac
    
    # Update status to PROCESSED
    update_event_status "$event_id" "$STATUS_PROCESSED"
    log_event "$event_id" "$user_name" "$event_type" "$STATUS_PROCESSED" "Event processed"
}

# Process POST event - add to feed
process_post_event() {
    local event_json="$1"
    local event_id=$(json_get "$event_json" "event_id")
    local user_id=$(json_get "$event_json" "user_id")
    local user_name=$(json_get "$event_json" "user_name")
    local content=$(json_get "$event_json" "content")
    local timestamp=$(json_get "$event_json" "timestamp")
    local post_id=$(generate_post_id)
    
    local post_json=$(json_object \
        "post_id" "$post_id" \
        "event_id" "$event_id" \
        "user_id" "$user_id" \
        "username" "$user_name" \
        "content" "$content" \
        "timestamp" "$timestamp" \
        "likes" "0" \
        "comments" "0" \
        "shares" "0" \
        "comments_data" "[]")
    
    # Save post
    atomic_write "${POSTS_DIR}/${post_id}.json" "$post_json"
    
    # Add to feed
    feed_add_post "$post_json"
    
    # Update stats
    stats_increment "total_posts"
    stats_increment "total_events"
    stats_increment "processed_events"
}

# Process LIKE event
process_like_event() {
    local event_json="$1"
    local target_post=$(json_get "$event_json" "target_post")
    
    if post_exists "$target_post"; then
        feed_increment_likes "$target_post"
        stats_increment "total_likes"
        stats_increment "total_events"
        stats_increment "processed_events"
    else
        log_warn "EVENT" "Target post not found for like: $target_post"
        update_event_status "$(json_get "$event_json" "event_id")" "$STATUS_FAILED"
    fi
}

# Process COMMENT event
process_comment_event() {
    local event_json="$1"
    local target_post=$(json_get "$event_json" "target_post")
    local content=$(json_get "$event_json" "content")
    local user_id=$(json_get "$event_json" "user_id")
    local user_name=$(json_get "$event_json" "user_name")
    local event_id=$(json_get "$event_json" "event_id")
    local timestamp=$(json_get "$event_json" "timestamp")
    
    if post_exists "$target_post"; then
        local comment_json=$(json_object \
            "comment_id" "$(generate_id "cmt_")" \
            "event_id" "$event_id" \
            "user_id" "$user_id" \
            "username" "$user_name" \
            "content" "$content" \
            "timestamp" "$timestamp")
        
        feed_add_comment "$target_post" "$comment_json"
        stats_increment "total_comments"
        stats_increment "total_events"
        stats_increment "processed_events"
    else
        log_warn "EVENT" "Target post not found for comment: $target_post"
        update_event_status "$event_id" "$STATUS_FAILED"
    fi
}

# Process SHARE event
process_share_event() {
    local event_json="$1"
    local target_post=$(json_get "$event_json" "target_post")
    
    if post_exists "$target_post"; then
        feed_increment_shares "$target_post"
        stats_increment "total_shares"
        stats_increment "total_events"
        stats_increment "processed_events"
    else
        log_warn "EVENT" "Target post not found for share: $target_post"
        update_event_status "$(json_get "$event_json" "event_id")" "$STATUS_FAILED"
    fi
}

# Process FOLLOW event
process_follow_event() {
    local event_json="$1"
    local user_id=$(json_get "$event_json" "user_id")
    local target_user=$(json_get "$event_json" "target_user")
    
    if user_exists "$target_user"; then
        stats_increment "total_follows"
        stats_increment "total_events"
        stats_increment "processed_events"
        log_event "$(json_get "$event_json" "event_id")" "$(json_get "$event_json" "user_name")" "$EVENT_FOLLOW" "$STATUS_PROCESSED" "Follow processed: $user_id -> $target_user"
    else
        log_warn "EVENT" "Target user not found for follow: $target_user"
        update_event_status "$(json_get "$event_json" "event_id")" "$STATUS_FAILED"
    fi
}

# Process NOTIFICATION event
process_notification_event() {
    local event_json="$1"
    stats_increment "total_events"
    stats_increment "processed_events"
    log_event "$(json_get "$event_json" "event_id")" "$(json_get "$event_json" "user_name")" "$EVENT_NOTIFICATION" "$STATUS_PROCESSED" "Notification processed"
}

# Get recent events
get_recent_events() {
    local limit="${1:-50}"
    local event_type="${2:-}"
    
    local files=("${EVENTS_DIR}"/*.json)
    [[ -f "${files[0]}" ]] || { echo "[]"; return; }
    
    local all_events="["
    local first=true
    
    # Sort by timestamp (newest first)
    for event_file in $(ls -t "${EVENTS_DIR}"/*.json 2>/dev/null | head -"$limit"); do
        [[ "$first" == true ]] || all_events+=","
        all_events+=$(cat "$event_file")
        first=false
    done
    
    all_events+="]"
    
    if [[ -n "$event_type" ]]; then
        echo "$all_events" | jq --arg type "$event_type" 'map(select(.event_type == $type))'
    else
        echo "$all_events"
    fi
}

# Export functions
export -f create_event create_post_event create_like_event create_comment_event
export -f create_share_event create_follow_event create_notification_event
export -f get_event update_event_status queue_event process_event
export -f process_post_event process_like_event process_comment_event
export -f process_share_event process_follow_event process_notification_event
export -f get_recent_events
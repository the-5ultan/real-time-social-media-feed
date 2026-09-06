#!/usr/bin/env bash
# Statistics Service
# Handles system statistics tracking and reporting

# Prevent multiple sourcing
[[ -n "${STATS_SERVICE_LOADED:-}" ]] && return 0
readonly STATS_SERVICE_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/../../config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/logger.sh"

# =============================================================================
# STATISTICS SERVICE
# =============================================================================

# Initialize statistics
stats_init() {
    [[ -f "$STATS_FILE" ]] || {
        local stats_json=$(json_object \
            "total_events" "0" \
            "processed_events" "0" \
            "pending_events" "0" \
            "total_posts" "0" \
            "total_likes" "0" \
            "total_comments" "0" \
            "total_shares" "0" \
            "total_follows" "0" \
            "active_producers" "0" \
            "active_workers" "0" \
            "processing_rate" "0" \
            "uptime_seconds" "0" \
            "last_updated" "$(get_timestamp)")
        atomic_write "$STATS_FILE" "$stats_json"
    }
    log_system "Statistics service initialized"
}

# Increment a counter
stats_increment() {
    local field="$1"
    local increment="${2:-1}"
    
    (
        flock -x 200
        local stats_json=$(read_file "$STATS_FILE")
        local new_stats=$(echo "$stats_json" | jq --arg f "$field" --argjson inc "$increment" '.[$f] += $inc | .last_updated = "'$(get_timestamp)'"')
        atomic_write "$STATS_FILE" "$new_stats"
    ) 200>"$STATS_LOCK"
}

# Decrement a counter
stats_decrement() {
    local field="$1"
    local decrement="${2:-1}"
    
    (
        flock -x 200
        local stats_json=$(read_file "$STATS_FILE")
        local new_stats=$(echo "$stats_json" | jq --arg f "$field" --argjson dec "$decrement" '.[$f] -= $dec | .last_updated = "'$(get_timestamp)'"')
        atomic_write "$STATS_FILE" "$new_stats"
    ) 200>"$STATS_LOCK"
}

# Set a gauge value
stats_set() {
    local field="$1"
    local value="$2"
    
    (
        flock -x 200
        local stats_json=$(read_file "$STATS_FILE")
        local new_stats=$(echo "$stats_json" | jq --arg f "$field" --argjson val "$value" '.[$f] = $val | .last_updated = "'$(get_timestamp)'"')
        atomic_write "$STATS_FILE" "$new_stats"
    ) 200>"$STATS_LOCK"
}

# Get statistic value
stats_get() {
    local field="$1"
    local stats_json=$(read_file "$STATS_FILE")
    echo "$stats_json" | jq --arg f "$field" '.[$f] // 0'
}

# Get all statistics
stats_get_all() {
    local stats_json=$(read_file "$STATS_FILE")
    echo "$stats_json"
}

# Update active producers count
stats_set_active_producers() {
    stats_set "active_producers" "$1"
}

# Update active workers count
stats_set_active_workers() {
    stats_set "active_workers" "$1"
}

# Update processing rate (events per second)
stats_update_processing_rate() {
    local rate="$1"
    stats_set "processing_rate" "$rate"
}

# Update uptime
stats_update_uptime() {
    local start_time="${STATS_START_TIME:-$(get_epoch_sec)}"
    local current_time=$(get_epoch_sec)
    local uptime=$((current_time - start_time))
    stats_set "uptime_seconds" "$uptime"
}

# Update pending events count
stats_update_pending() {
    local queue_size=$(queue_size)
    stats_set "pending_events" "$queue_size"
}

# Reset statistics
stats_reset() {
    (
        flock -x 200
        local stats_json=$(json_object \
            "total_events" "0" \
            "processed_events" "0" \
            "pending_events" "0" \
            "total_posts" "0" \
            "total_likes" "0" \
            "total_comments" "0" \
            "total_shares" "0" \
            "total_follows" "0" \
            "active_producers" "0" \
            "active_workers" "0" \
            "processing_rate" "0" \
            "uptime_seconds" "0" \
            "last_updated" "$(get_timestamp)")
        atomic_write "$STATS_FILE" "$stats_json"
    ) 200>"$STATS_LOCK"
    log_system "Statistics reset"
}

# Get formatted statistics for display
stats_get_display() {
    local stats_json=$(stats_get_all)
    
    local total_events=$(json_get_num "$stats_json" "total_events")
    local processed_events=$(json_get_num "$stats_json" "processed_events")
    local pending_events=$(json_get_num "$stats_json" "pending_events")
    local total_posts=$(json_get_num "$stats_json" "total_posts")
    local total_likes=$(json_get_num "$stats_json" "total_likes")
    local total_comments=$(json_get_num "$stats_json" "total_comments")
    local total_shares=$(json_get_num "$stats_json" "total_shares")
    local total_follows=$(json_get_num "$stats_json" "total_follows")
    local active_producers=$(json_get_num "$stats_json" "active_producers")
    local active_workers=$(json_get_num "$stats_json" "active_workers")
    local processing_rate=$(json_get_num "$stats_json" "processing_rate")
    local uptime=$(json_get_num "$stats_json" "uptime_seconds")
    local last_updated=$(json_get "$stats_json" "last_updated")
    
    json_object \
        "total_events" "$total_events" \
        "processed_events" "$processed_events" \
        "pending_events" "$pending_events" \
        "total_posts" "$total_posts" \
        "total_likes" "$total_likes" \
        "total_comments" "$total_comments" \
        "total_shares" "$total_shares" \
        "total_follows" "$total_follows" \
        "active_producers" "$active_producers" \
        "active_workers" "$active_workers" \
        "processing_rate" "$processing_rate" \
        "uptime_seconds" "$uptime" \
        "uptime_formatted" "$(format_uptime "$uptime")" \
        "last_updated" "$last_updated"
}

# Format uptime seconds to human readable
format_uptime() {
    local seconds="$1"
    local days=$((seconds / 86400))
    local hours=$(( (seconds % 86400) / 3600 ))
    local minutes=$(( (seconds % 3600) / 60 ))
    local secs=$((seconds % 60))
    
    if [[ $days -gt 0 ]]; then
        printf "%dd %dh %dm" "$days" "$hours" "$minutes"
    elif [[ $hours -gt 0 ]]; then
        printf "%dh %dm" "$hours" "$minutes"
    elif [[ $minutes -gt 0 ]]; then
        printf "%dm %ds" "$minutes" "$secs"
    else
        printf "%ds" "$secs"
    fi
}

# Export functions
export -f stats_init stats_increment stats_decrement stats_set stats_get stats_get_all
export -f stats_set_active_producers stats_set_active_workers stats_update_processing_rate
export -f stats_update_uptime stats_update_pending stats_reset stats_get_display format_uptime
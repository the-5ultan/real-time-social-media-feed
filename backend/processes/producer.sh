#!/usr/bin/env bash
# Producer Process
# Generates social media events and enqueues them

set -Eeuo pipefail

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "${PROJECT_ROOT}/backend/config.sh"
source "${PROJECT_ROOT}/backend/utils/common.sh"
source "${PROJECT_ROOT}/backend/utils/logger.sh"
source "${PROJECT_ROOT}/backend/utils/validation.sh"
source "${PROJECT_ROOT}/backend/datastructures/queue.sh"
source "${PROJECT_ROOT}/backend/datastructures/priority_queue.sh"
source "${PROJECT_ROOT}/backend/services/event_service.sh"
source "${PROJECT_ROOT}/backend/services/user_service.sh"
source "${PROJECT_ROOT}/backend/services/statistics_service.sh"

# =============================================================================
# PRODUCER CONFIGURATION
# =============================================================================

PRODUCER_ID="${1:-producer-$$}"
PRODUCER_INTERVAL="${PRODUCER_INTERVAL:-2}"
USE_PRIORITY_QUEUE="${USE_PRIORITY_QUEUE:-false}"

# Event generation weights (higher = more likely)
declare -A EVENT_WEIGHTS=(
    ["POST"]=10
    ["LIKE"]=30
    ["COMMENT"]=15
    ["SHARE"]=10
    ["FOLLOW"]=5
    ["NOTIFICATION"]=3
)

# Sample content for posts
POST_CONTENTS=(
    "Working on my OS project! #bash #systems"
    "Multiprocessing is fascinating"
    "Just learned about FIFOs and IPC"
    "Race conditions are tricky but flock helps"
    "Dynamic data structures in Bash? Yes!"
    "Process management is so cool"
    "Producer-consumer pattern in action"
    "Real-time feed with Bash backend"
    "Operating Systems concepts in practice"
    "Synchronization with flock is elegant"
)

# Sample comments
COMMENT_CONTENTS=(
    "Great post!"
    "Thanks for sharing"
    "Very interesting"
    "I agree"
    "Nice work!"
    "Keep it up"
    "Learn something new every day"
    "This is awesome"
)

# =============================================================================
# PRODUCER FUNCTIONS
# =============================================================================

# Initialize producer
producer_init() {
    log_producer "$PRODUCER_ID" "" "" "Producer initialized" "$$"
    stats_increment "active_producers"
    
    # Setup signal handlers
    trap 'producer_shutdown' EXIT INT TERM
}

# Shutdown producer
producer_shutdown() {
    log_producer "$PRODUCER_ID" "" "" "Producer shutting down" "$$"
    stats_decrement "active_producers"
}

# Get random user
get_random_user() {
    local user=$(get_random_user)
    if [[ -n "$user" && "$user" != "null" ]]; then
        echo "$user"
    else
        # Fallback to default users
        local idx=$((RANDOM % ${#DEFAULT_USERS[@]}))
        local username="${DEFAULT_USERS[$idx]}"
        local user_id="user_${username,,}"
        json_object "user_id" "$user_id" "username" "$username"
    fi
}

# Select random event type based on weights
select_event_type() {
    local total=0
    for weight in "${EVENT_WEIGHTS[@]}"; do
        ((total += weight))
    done
    
    local rand=$((RANDOM % total + 1))
    local cumulative=0
    
    for event_type in "${!EVENT_WEIGHTS[@]}"; do
        ((cumulative += EVENT_WEIGHTS[$event_type]))
        if [[ $rand -le $cumulative ]]; then
            echo "$event_type"
            return
        fi
    done
    
    echo "POST"
}

# Generate random post content
generate_post_content() {
    local idx=$((RANDOM % ${#POST_CONTENTS[@]}))
    echo "${POST_CONTENTS[$idx]}"
}

# Generate random comment content
generate_comment_content() {
    local idx=$((RANDOM % ${#COMMENT_CONTENTS[@]}))
    echo "${COMMENT_CONTENTS[$idx]}"
}

# Get random existing post ID
get_random_post_id() {
    local posts=$(feed_get_all)
    local count=$(echo "$posts" | jq 'length')
    [[ $count -gt 0 ]] || return 1
    
    local idx=$((RANDOM % count))
    echo "$posts" | jq -r ".[$idx].post_id"
}

# Get random existing user ID
get_random_user_id() {
    local users=$(get_all_users)
    local count=$(echo "$users" | jq 'length')
    [[ $count -gt 0 ]] || return 1
    
    local idx=$((RANDOM % count))
    echo "$users" | jq -r ".[$idx].user_id"
}

# Generate event
generate_event() {
    local user=$(get_random_user)
    [[ -n "$user" && "$user" != "null" ]] || return 1
    
    local user_id=$(json_get "$user" "user_id")
    local user_name=$(json_get "$user" "username")
    local event_type=$(select_event_type)
    local priority
    
    case "$event_type" in
        "$EVENT_POST")
            local content=$(generate_post_content)
            priority=$PRIORITY_POST
            create_post_event "$user_id" "$user_name" "$content" "$priority"
            ;;
        "$EVENT_LIKE")
            local target_post=$(get_random_post_id)
            [[ -n "$target_post" ]] || return 1
            priority=$PRIORITY_LIKE
            create_like_event "$user_id" "$user_name" "$target_post" "$priority"
            ;;
        "$EVENT_COMMENT")
            local target_post=$(get_random_post_id)
            [[ -n "$target_post" ]] || return 1
            local content=$(generate_comment_content)
            priority=$PRIORITY_COMMENT
            create_comment_event "$user_id" "$user_name" "$target_post" "$content" "$priority"
            ;;
        "$EVENT_SHARE")
            local target_post=$(get_random_post_id)
            [[ -n "$target_post" ]] || return 1
            priority=$PRIORITY_SHARE
            create_share_event "$user_id" "$user_name" "$target_post" "$priority"
            ;;
        "$EVENT_FOLLOW")
            local target_user=$(get_random_user_id)
            [[ -n "$target_user" && "$target_user" != "$user_id" ]] || return 1
            priority=$PRIORITY_FOLLOW
            create_follow_event "$user_id" "$user_name" "$target_user" "$priority"
            ;;
        "$EVENT_NOTIFICATION")
            local content="System notification for $user_name"
            priority=$PRIORITY_NOTIFICATION
            create_notification_event "$user_id" "$user_name" "$content" "$priority"
            ;;
    esac
}

# Main producer loop
producer_run() {
    log_producer "$PRODUCER_ID" "" "" "Producer started, interval: ${PRODUCER_INTERVAL}s" "$$"
    
    while true; do
        # Generate and queue event
        local event_json=$(generate_event)
        if [[ -n "$event_json" ]]; then
            queue_event "$event_json" "$USE_PRIORITY_QUEUE"
        fi
        
        # Sleep with small random jitter
        local jitter=$((RANDOM % 500))
        local sleep_time=$(echo "$PRODUCER_INTERVAL + $jitter / 1000" | bc -l 2>/dev/null || echo "$PRODUCER_INTERVAL")
        sleep "$sleep_time"
    done
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    producer_init
    producer_run
}

main "$@"
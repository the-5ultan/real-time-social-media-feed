#!/usr/bin/env bash
# Feed Service
# High-level feed operations combining feed data structure with user service

# Prevent multiple sourcing
[[ -n "${FEED_SERVICE_LOADED:-}" ]] && return 0
readonly FEED_SERVICE_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/../../config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/feed.sh"
source "$(dirname "${BASH_SOURCE[0]}")/user_service.sh"
source "$(dirname "${BASH_SOURCE[0]}")/event_service.sh"

# =============================================================================
# FEED SERVICE
# =============================================================================

# Initialize feed service
feed_service_init() {
    feed_init
    users_init
    log_system "Feed service initialized"
}

# Create post and add to feed
create_post() {
    local user_id="$1"
    local content="$2"
    
    local user=$(get_user "$user_id")
    [[ -n "$user" ]] || { echo "User not found" >&2; return 1; }
    
    local user_name=$(json_get "$user" "username")
    
    # Create event
    local event_json=$(create_post_event "$user_id" "$user_name" "$content")
    local event_id=$(json_get "$event_json" "event_id")
    
    # Queue for processing
    queue_event "$event_json"
    
    # Update user stats
    increment_posts "$user_id"
    
    echo "$event_json"
}

# Like a post
like_post() {
    local user_id="$1"
    local post_id="$2"
    
    local user=$(get_user "$user_id")
    [[ -n "$user" ]] || { echo "User not found" >&2; return 1; }
    
    local user_name=$(json_get "$user" "username")
    
    # Verify post exists
    post_exists "$post_id" || { echo "Post not found" >&2; return 1; }
    
    # Create event
    local event_json=$(create_like_event "$user_id" "$user_name" "$post_id")
    queue_event "$event_json"
    
    echo "$event_json"
}

# Comment on a post
comment_post() {
    local user_id="$1"
    local post_id="$2"
    local content="$3"
    
    local user=$(get_user "$user_id")
    [[ -n "$user" ]] || { echo "User not found" >&2; return 1; }
    
    local user_name=$(json_get "$user" "username")
    
    post_exists "$post_id" || { echo "Post not found" >&2; return 1; }
    
    local event_json=$(create_comment_event "$user_id" "$user_name" "$post_id" "$content")
    queue_event "$event_json"
    
    echo "$event_json"
}

# Share a post
share_post() {
    local user_id="$1"
    local post_id="$2"
    
    local user=$(get_user "$user_id")
    [[ -n "$user" ]] || { echo "User not found" >&2; return 1; }
    
    local user_name=$(json_get "$user" "username")
    
    post_exists "$post_id" || { echo "Post not found" >&2; return 1; }
    
    local event_json=$(create_share_event "$user_id" "$user_name" "$post_id")
    queue_event "$event_json"
    
    echo "$event_json"
}

# Follow user
follow_user() {
    local user_id="$1"
    local target_user_id="$2"
    
    [[ "$user_id" != "$target_user_id" ]] || { echo "Cannot follow yourself" >&2; return 1; }
    
    local user=$(get_user "$user_id")
    local target_user=$(get_user "$target_user_id")
    [[ -n "$user" && -n "$target_user" ]] || { echo "User not found" >&2; return 1; }
    
    local user_name=$(json_get "$user" "username")
    local target_user_name=$(json_get "$target_user" "username")
    
    local event_json=$(create_follow_event "$user_id" "$user_name" "$target_user_id")
    queue_event "$event_json"
    
    # Update stats
    increment_following "$user_id"
    increment_followers "$target_user_id"
    
    echo "$event_json"
}

# Get feed for display
get_feed_display() {
    local page="${1:-1}"
    local page_size="${2:-20}"
    
    local posts=$(feed_get_page "$page" "$page_size")
    local stats=$(feed_get_stats)
    
    json_object \
        "posts" "$posts" \
        "stats" "$stats" \
        "page" "$page" \
        "page_size" "$page_size"
}

# Get single post with details
get_post_details() {
    local post_id="$1"
    local post=$(feed_find_post "$post_id")
    
    if [[ -n "$post" && "$post" != "null" ]]; then
        # Enrich with user info
        local user_id=$(json_get "$post" "user_id")
        local user=$(get_user "$user_id")
        local username=$(json_get "$user" "username")
        
        echo "$post" | jq --arg uname "$username" '. + {username: $uname}'
    else
        echo ""
    fi
}

# Search feed
search_feed() {
    local query="$1"
    local page="${2:-1}"
    local page_size="${3:-20}"
    
    local results=$(feed_search_posts "$query")
    local total=$(echo "$results" | jq 'length')
    local offset=$(( (page - 1) * page_size ))
    local paged=$(echo "$results" | jq --argjson off "$offset" --argjson sz "$page_size" '.[$off:$off+$sz]')
    
    json_object \
        "posts" "$paged" \
        "total" "$total" \
        "page" "$page" \
        "page_size" "$page_size"
}

# Get user's posts
get_user_feed() {
    local user_id="$1"
    local page="${2:-1}"
    local page_size="${3:-20}"
    
    local results=$(feed_search_by_user "$user_id")
    local total=$(echo "$results" | jq 'length')
    local offset=$(( (page - 1) * page_size ))
    local paged=$(echo "$results" | jq --argjson off "$offset" --argjson sz "$page_size" '.[$off:$off+$sz]')
    
    json_object \
        "posts" "$paged" \
        "total" "$total" \
        "page" "$page" \
        "page_size" "$page_size"
}

# Get feed statistics
get_feed_statistics() {
    local feed_stats=$(feed_get_stats)
    local user_count=$(get_user_count)
    local queue_stats=$(queue_get_stats)
    
    json_object \
        "feed" "$feed_stats" \
        "users" "$user_count" \
        "queue" "$queue_stats"
}

# Export functions
export -f feed_service_init create_post like_post comment_post share_post follow_user
export -f get_feed_display get_post_details search_feed get_user_feed get_feed_statistics
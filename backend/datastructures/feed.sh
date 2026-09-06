#!/usr/bin/env bash
# Dynamic Feed Data Structure
# Implements a linked-list-style feed with insert, delete, search, update, traverse operations

# Prevent multiple sourcing
[[ -n "${FEED_DS_LOADED:-}" ]] && return 0
readonly FEED_DS_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/../../config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/validation.sh"

# =============================================================================
# FEED DATA STRUCTURE
# =============================================================================

# Feed is stored as JSON array in FEED_FILE
# Each post: {post_id, user_id, username, content, timestamp, likes, comments, shares, followers}

# Initialize feed file
feed_init() {
    local feed_file="${1:-$FEED_FILE}"
    [[ -f "$feed_file" ]] || atomic_write "$feed_file" "[]"
    log_feed "INIT" "" "Feed initialized at $feed_file"
}

# Get feed size
feed_size() {
    local feed_file="${1:-$FEED_FILE}"
    local content=$(read_file "$feed_file")
    echo "$content" | jq 'length' 2>/dev/null || echo 0
}

# Check if feed is empty
feed_is_empty() {
    [[ $(feed_size "$1") -eq 0 ]]
}

# Add post to feed (insert at front for reverse chronological)
feed_add_post() {
    local post_json="$1"
    local feed_file="${2:-$FEED_FILE}"
    
    validate_post "$post_json" || return 1
    
    (
        flock -x 200
        local content=$(read_file "$feed_file")
        local new_feed=$(echo "$content" | jq --argjson post "$post_json" '[$post] + .')
        
        # Trim to max size
        new_feed=$(echo "$new_feed" | jq --argjson max "$FEED_MAX_POSTS" '.[:$max]')
        
        atomic_write "$feed_file" "$new_feed"
        
        local post_id=$(json_get "$post_json" "post_id")
        log_feed "ADD" "$post_id" "Post added to feed (size: $(feed_size "$feed_file"))"
    ) 200>"$FEED_LOCK"
}

# Remove post from feed
feed_remove_post() {
    local post_id="$1"
    local feed_file="${2:-$FEED_FILE}"
    
    (
        flock -x 200
        local content=$(read_file "$feed_file")
        local new_feed=$(echo "$content" | jq --arg pid "$post_id" 'map(select(.post_id != $pid))')
        atomic_write "$feed_file" "$new_feed"
        log_feed "REMOVE" "$post_id" "Post removed from feed (size: $(feed_size "$feed_file"))"
    ) 200>"$FEED_LOCK"
}

# Update post in feed
feed_update_post() {
    local post_id="$1"
    local updates_json="$2"
    local feed_file="${3:-$FEED_FILE}"
    
    (
        flock -x 200
        local content=$(read_file "$feed_file")
        local new_feed=$(echo "$content" | jq --arg pid "$post_id" --argjson updates "$updates_json" '
            map(if .post_id == $pid then . + $updates else . end)
        ')
        atomic_write "$feed_file" "$new_feed"
        log_feed "UPDATE" "$post_id" "Post updated in feed"
    ) 200>"$FEED_LOCK"
}

# Find post by ID
feed_find_post() {
    local post_id="$1"
    local feed_file="${2:-$FEED_FILE}"
    local content=$(read_file "$feed_file")
    echo "$content" | jq --arg pid "$post_id" 'map(select(.post_id == $pid))[0] // empty'
}

# Search posts by content (case-insensitive)
feed_search_posts() {
    local query="$1"
    local feed_file="${2:-$FEED_FILE}"
    local content=$(read_file "$feed_file")
    echo "$content" | jq --arg q "$query" 'map(select(.content | lower | contains($q | lower)))'
}

# Search posts by user
feed_search_by_user() {
    local user_id="$1"
    local feed_file="${2:-$FEED_FILE}"
    local content=$(read_file "$feed_file")
    echo "$content" | jq --arg uid "$user_id" 'map(select(.user_id == $uid))'
}

# Get all posts (traverse)
feed_get_all() {
    local feed_file="${1:-$FEED_FILE}"
    local limit="${2:-0}"
    local content=$(read_file "$feed_file")
    
    if [[ $limit -gt 0 ]]; then
        echo "$content" | jq --argjson lim "$limit" '.[:$lim]'
    else
        echo "$content"
    fi
}

# Get posts with pagination
feed_get_page() {
    local page="${1:-1}"
    local page_size="${2:-20}"
    local feed_file="${3:-$FEED_FILE}"
    local content=$(read_file "$feed_file")
    local offset=$(( (page - 1) * page_size ))
    echo "$content" | jq --argjson off "$offset" --argjson sz "$page_size" '.[$off:$off+$sz]'
}

# Increment like count
feed_increment_likes() {
    local post_id="$1"
    local feed_file="${2:-$FEED_FILE}"
    feed_update_post "$post_id" '{"likes": (.likes + 1)}' "$feed_file"
}

# Decrement like count
feed_decrement_likes() {
    local post_id="$1"
    local feed_file="${2:-$FEED_FILE}"
    feed_update_post "$post_id" '{"likes": (.likes - 1)}' "$feed_file"
}

# Increment comment count
feed_increment_comments() {
    local post_id="$1"
    local feed_file="${2:-$FEED_FILE}"
    feed_update_post "$post_id" '{"comments": (.comments + 1)}' "$feed_file"
}

# Increment share count
feed_increment_shares() {
    local post_id="$1"
    local feed_file="${2:-$FEED_FILE}"
    feed_update_post "$post_id" '{"shares": (.shares + 1)}' "$feed_file"
}

# Add comment to post
feed_add_comment() {
    local post_id="$1"
    local comment_json="$2"
    local feed_file="${3:-$FEED_FILE}"
    
    (
        flock -x 200
        local content=$(read_file "$feed_file")
        local new_feed=$(echo "$content" | jq --arg pid "$post_id" --argjson comment "$comment_json" '
            map(if .post_id == $pid then 
                .comments_data = (.comments_data // [] + [$comment]) | 
                .comments = (.comments + 1)
            else . end)
        ')
        atomic_write "$feed_file" "$new_feed"
        log_feed "COMMENT_ADD" "$post_id" "Comment added to post"
    ) 200>"$FEED_LOCK"
}

# Get feed statistics
feed_get_stats() {
    local feed_file="${1:-$FEED_FILE}"
    local content=$(read_file "$feed_file")
    local total=$(echo "$content" | jq 'length')
    local total_likes=$(echo "$content" | jq '[.[]?.likes // 0] | add // 0')
    local total_comments=$(echo "$content" | jq '[.[]?.comments // 0] | add // 0')
    local total_shares=$(echo "$content" | jq '[.[]?.shares // 0] | add // 0')
    
    json_object \
        "total_posts" "$total" \
        "total_likes" "$total_likes" \
        "total_comments" "$total_comments" \
        "total_shares" "$total_shares"
}

# Export functions
export -f feed_init feed_size feed_is_empty
export -f feed_add_post feed_remove_post feed_update_post
export -f feed_find_post feed_search_posts feed_search_by_user
export -f feed_get_all feed_get_page
export -f feed_increment_likes feed_decrement_likes
export -f feed_increment_comments feed_increment_shares
export -f feed_add_comment feed_get_stats
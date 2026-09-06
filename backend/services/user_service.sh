#!/usr/bin/env bash
# User Service
# Handles user creation, retrieval, and management

# Prevent multiple sourcing
[[ -n "${USER_SERVICE_LOADED:-}" ]] && return 0
readonly USER_SERVICE_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/../../config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/validation.sh"

# =============================================================================
# USER SERVICE
# =============================================================================

# Initialize users
users_init() {
    [[ -f "$USERS_FILE" ]] || atomic_write "$USERS_FILE" "[]"
    log_system "User service initialized"
}

# Create user
create_user() {
    local username="$1"
    
    validate_not_empty "$username" "username" || return 1
    [[ "$username" =~ ^[a-zA-Z0-9_]{3,30}$ ]] || { echo "Invalid username format" >&2; return 1; }
    
    # Check if username exists
    local existing=$(get_user_by_username "$username")
    [[ -z "$existing" ]] || { echo "Username already exists" >&2; return 1; }
    
    local user_id=$(generate_user_id)
    local timestamp=$(get_timestamp)
    
    local user_json=$(json_object \
        "user_id" "$user_id" \
        "username" "$username" \
        "created_at" "$timestamp" \
        "followers_count" "0" \
        "following_count" "0" \
        "posts_count" "0")
    
    (
        flock -x 200
        atomic_write "${USERS_DIR}/${user_id}.json" "$user_json"
        
        # Update index
        local users_index=$(read_file "$USERS_FILE")
        local new_index=$(echo "$users_index" | jq --argjson user "$user_json" '. + [$user]')
        atomic_write "$USERS_FILE" "$new_index"
    ) 200>"$USERS_LOCK"
    
    log_system "User created: $username ($user_id)"
    echo "$user_json"
}

# Get user by ID
get_user() {
    local user_id="$1"
    local user_file="${USERS_DIR}/${user_id}.json"
    [[ -f "$user_file" ]] && cat "$user_file" || echo ""
}

# Get user by username
get_user_by_username() {
    local username="$1"
    local users_index=$(read_file "$USERS_FILE")
    echo "$users_index" | jq --arg name "$username" 'map(select(.username == $name))[0] // empty'
}

# Get all users
get_all_users() {
    local limit="${1:-0}"
    local users_index=$(read_file "$USERS_FILE")
    
    if [[ $limit -gt 0 ]]; then
        echo "$users_index" | jq --argjson lim "$limit" '.[:$lim]'
    else
        echo "$users_index"
    fi
}

# Get random user
get_random_user() {
    local users_index=$(read_file "$USERS_FILE")
    local count=$(echo "$users_index" | jq 'length')
    [[ $count -gt 0 ]] || { echo ""; return 1; }
    
    local index=$((RANDOM % count))
    echo "$users_index" | jq --argjson idx "$index" '.[$idx]'
}

# Update user stats
update_user_stats() {
    local user_id="$1"
    local field="$2"
    local increment="${3:-1}"
    
    local user_file="${USERS_DIR}/${user_id}.json"
    [[ -f "$user_file" ]] || return 1
    
    (
        flock -x 200
        local user_json=$(cat "$user_file")
        local new_value=$(echo "$user_json" | jq --arg f "$field" --argjson inc "$increment" '.[$f] += $inc')
        atomic_write "$user_file" "$new_value"
        
        # Update index
        local users_index=$(read_file "$USERS_FILE")
        local new_index=$(echo "$users_index" | jq --arg uid "$user_id" --argjson user "$new_value" 'map(if .user_id == $uid then $user else . end)')
        atomic_write "$USERS_FILE" "$new_index"
    ) 200>"$USERS_LOCK"
}

# Increment followers
increment_followers() {
    update_user_stats "$1" "followers_count" "${2:-1}"
}

# Increment following
increment_following() {
    update_user_stats "$1" "following_count" "${2:-1}"
}

# Increment posts
increment_posts() {
    update_user_stats "$1" "posts_count" "${2:-1}"
}

# Search users
search_users() {
    local query="$1"
    local users_index=$(read_file "$USERS_FILE")
    echo "$users_index" | jq --arg q "$query" 'map(select(.username | lower | contains($q | lower)))'
}

# Get user count
get_user_count() {
    local users_index=$(read_file "$USERS_FILE")
    echo "$users_index" | jq 'length'
}

# Export functions
export -f users_init create_user get_user get_user_by_username
export -f get_all_users get_random_user update_user_stats
export -f increment_followers increment_following increment_posts
export -f search_users get_user_count
#!/usr/bin/env bash
# Event Simulator
# Generates bursts of events for demonstration

set -Eeuo pipefail

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "${PROJECT_ROOT}/backend/config.sh"
source "${PROJECT_ROOT}/backend/utils/common.sh"
source "${PROJECT_ROOT}/backend/utils/logger.sh"
source "${PROJECT_ROOT}/backend/services/event_service.sh"
source "${PROJECT_ROOT}/backend/services/user_service.sh"
source "${PROJECT_ROOT}/backend/services/statistics_service.sh"

# =============================================================================
# SIMULATOR CONFIGURATION
# =============================================================================

SIMULATION_DURATION="${SIMULATION_DURATION:-60}"
EVENT_BURST_SIZE="${SIMULATION_EVENT_BURST:-10}"
BURST_INTERVAL=5

# Demo scenarios
DEMO_SCENARIOS=(
    "burst_posts"
    "burst_interactions"
    "mixed_activity"
    "notification_storm"
)

# =============================================================================
# SIMULATOR FUNCTIONS
# =============================================================================

simulator_init() {
    log_process "simulator" "START" "$$" "Event simulator initialized"
    trap 'simulator_shutdown' EXIT INT TERM
}

simulator_shutdown() {
    log_process "simulator" "STOP" "$$" "Event simulator shutting down"
}

# Scenario: Burst of posts
burst_posts() {
    log_system "Simulator: Generating burst of posts"
    local users=$(get_all_users)
    local count=$(echo "$users" | jq 'length')
    
    for i in $(seq 1 "$EVENT_BURST_SIZE"); do
        local idx=$((RANDOM % count))
        local user=$(echo "$users" | jq ".[$idx]")
        local user_id=$(json_get "$user" "user_id")
        local user_name=$(json_get "$user" "username")
        local content="Simulated post #$i from $user_name at $(get_timestamp)"
        
        local event_json=$(create_post_event "$user_id" "$user_name" "$content" "$PRIORITY_POST")
        queue_event "$event_json"
        sleep 0.1
    done
}

# Scenario: Burst of interactions (likes, comments, shares)
burst_interactions() {
    log_system "Simulator: Generating burst of interactions"
    local posts=$(feed_get_all)
    local post_count=$(echo "$posts" | jq 'length')
    local users=$(get_all_users)
    local user_count=$(echo "$users" | jq 'length')
    
    [[ $post_count -gt 0 ]] || return
    
    for i in $(seq 1 "$EVENT_BURST_SIZE"); do
        local post_idx=$((RANDOM % post_count))
        local post=$(echo "$posts" | jq ".[$post_idx]")
        local target_post=$(json_get "$post" "post_id")
        
        local user_idx=$((RANDOM % user_count))
        local user=$(echo "$users" | jq ".[$user_idx]")
        local user_id=$(json_get "$user" "user_id")
        local user_name=$(json_get "$user" "username")
        
        local event_type=$((RANDOM % 3))
        case $event_type in
            0) # LIKE
                local event_json=$(create_like_event "$user_id" "$user_name" "$target_post" "$PRIORITY_LIKE")
                ;;
            1) # COMMENT
                local content="Simulated comment #$i on post"
                local event_json=$(create_comment_event "$user_id" "$user_name" "$target_post" "$content" "$PRIORITY_COMMENT")
                ;;
            2) # SHARE
                local event_json=$(create_share_event "$user_id" "$user_name" "$target_post" "$PRIORITY_SHARE")
                ;;
        esac
        
        queue_event "$event_json"
        sleep 0.1
    done
}

# Scenario: Mixed activity
mixed_activity() {
    log_system "Simulator: Generating mixed activity"
    local users=$(get_all_users)
    local user_count=$(echo "$users" | jq 'length')
    local posts=$(feed_get_all)
    local post_count=$(echo "$posts" | jq 'length')
    
    for i in $(seq 1 "$EVENT_BURST_SIZE"); do
        local user_idx=$((RANDOM % user_count))
        local user=$(echo "$users" | jq ".[$user_idx]")
        local user_id=$(json_get "$user" "user_id")
        local user_name=$(json_get "$user" "username")
        
        local action=$((RANDOM % 5))
        case $action in
            0) # POST
                local content="Mixed activity post #$i from $user_name"
                local event_json=$(create_post_event "$user_id" "$user_name" "$content" "$PRIORITY_POST")
                ;;
            1) # LIKE (needs post)
                if [[ $post_count -gt 0 ]]; then
                    local post_idx=$((RANDOM % post_count))
                    local post=$(echo "$posts" | jq ".[$post_idx]")
                    local target_post=$(json_get "$post" "post_id")
                    local event_json=$(create_like_event "$user_id" "$user_name" "$target_post" "$PRIORITY_LIKE")
                else
                    continue
                fi
                ;;
            2) # COMMENT
                if [[ $post_count -gt 0 ]]; then
                    local post_idx=$((RANDOM % post_count))
                    local post=$(echo "$posts" | jq ".[$post_idx]")
                    local target_post=$(json_get "$post" "post_id")
                    local content="Mixed comment #$i"
                    local event_json=$(create_comment_event "$user_id" "$user_name" "$target_post" "$content" "$PRIORITY_COMMENT")
                else
                    continue
                fi
                ;;
            3) # SHARE
                if [[ $post_count -gt 0 ]]; then
                    local post_idx=$((RANDOM % post_count))
                    local post=$(echo "$posts" | jq ".[$post_idx]")
                    local target_post=$(json_get "$post" "post_id")
                    local event_json=$(create_share_event "$user_id" "$user_name" "$target_post" "$PRIORITY_SHARE")
                else
                    continue
                fi
                ;;
            4) # FOLLOW
                local target_idx=$((RANDOM % user_count))
                [[ $target_idx -ne $user_idx ]] || target_idx=$(( (target_idx + 1) % user_count ))
                local target_user=$(echo "$users" | jq ".[$target_idx]")
                local target_user_id=$(json_get "$target_user" "user_id")
                local event_json=$(create_follow_event "$user_id" "$user_name" "$target_user_id" "$PRIORITY_FOLLOW")
                ;;
        esac
        
        queue_event "$event_json"
        sleep 0.1
    done
}

# Scenario: Notification storm
notification_storm() {
    log_system "Simulator: Generating notification storm"
    local users=$(get_all_users)
    local count=$(echo "$users" | jq 'length')
    
    for i in $(seq 1 "$EVENT_BURST_SIZE"); do
        local idx=$((RANDOM % count))
        local user=$(echo "$users" | jq ".[$idx]")
        local user_id=$(json_get "$user" "user_id")
        local user_name=$(json_get "$user" "username")
        local content="Notification #$i for $user_name"
        
        local event_json=$(create_notification_event "$user_id" "$user_name" "$content" "$PRIORITY_NOTIFICATION")
        queue_event "$event_json"
        sleep 0.05
    done
}

# Run random scenario
run_random_scenario() {
    local scenario=${DEMO_SCENARIOS[$((RANDOM % ${#DEMO_SCENARIOS[@]}))]}
    log_system "Simulator: Running scenario: $scenario"
    $scenario
}

# Main simulator loop
simulator_run() {
    log_process "simulator" "RUN" "$$" "Event simulator running for ${SIMULATION_DURATION}s"
    
    local end_time=$(($(get_epoch_sec) + SIMULATION_DURATION))
    
    while [[ $(get_epoch_sec) -lt $end_time ]]; do
        run_random_scenario
        sleep "$BURST_INTERVAL"
    done
    
    log_process "simulator" "COMPLETE" "$$" "Simulation duration completed"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    simulator_init
    simulator_run
}

main "$@"
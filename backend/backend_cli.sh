#!/usr/bin/env bash
# CLI Interface for Backend Services
# Provides command-line access to all backend functions for the API server

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "${PROJECT_ROOT}/backend/config.sh"
source "${PROJECT_ROOT}/backend/utils/common.sh"
source "${PROJECT_ROOT}/backend/utils/logger.sh"
source "${PROJECT_ROOT}/backend/datastructures/feed.sh"
source "${PROJECT_ROOT}/backend/datastructures/queue.sh"
source "${PROJECT_ROOT}/backend/datastructures/priority_queue.sh"
source "${PROJECT_ROOT}/backend/services/user_service.sh"
source "${PROJECT_ROOT}/backend/services/event_service.sh"
source "${PROJECT_ROOT}/backend/services/feed_service.sh"
source "${PROJECT_ROOT}/backend/services/statistics_service.sh"
source "${PROJECT_ROOT}/backend/processes/manager.sh"
source "${PROJECT_ROOT}/backend/system/process_manager.sh"
source "${PROJECT_ROOT}/backend/system/resource_monitor.sh"
source "${PROJECT_ROOT}/backend/system/cleanup.sh"

# =============================================================================
# COMMAND DISPATCHER
# =============================================================================

main() {
    local cmd="${1:-help}"
    shift || true
    
    case "$cmd" in
        # Status commands
        "status")
            get_process_status
            ;;
        "health")
            system_health
            ;;
        
        # Feed commands
        "feed:init")
            feed_init
            ;;
        "feed:add")
            local post_json="$1"
            feed_add_post "$post_json"
            ;;
        "feed:remove")
            local post_id="$1"
            feed_remove_post "$post_id"
            ;;
        "feed:update")
            local post_id="$1"
            local updates_json="$2"
            feed_update_post "$post_id" "$updates_json"
            ;;
        "feed:find")
            local post_id="$1"
            feed_find_post "$post_id"
            ;;
        "feed:search")
            local query="$1"
            feed_search_posts "$query"
            ;;
        "feed:search-user")
            local user_id="$1"
            feed_search_by_user "$user_id"
            ;;
        "feed:get-all")
            local limit="${1:-0}"
            feed_get_all "$limit"
            ;;
        "feed:page")
            local page="${1:-1}"
            local page_size="${2:-20}"
            feed_get_page "$page" "$page_size"
            ;;
        "feed:like")
            local post_id="$1"
            feed_increment_likes "$post_id"
            ;;
        "feed:unlike")
            local post_id="$1"
            feed_decrement_likes "$post_id"
            ;;
        "feed:comment-inc")
            local post_id="$1"
            feed_increment_comments "$post_id"
            ;;
        "feed:share-inc")
            local post_id="$1"
            feed_increment_shares "$post_id"
            ;;
        "feed:comment-add")
            local post_id="$1"
            local comment_json="$2"
            feed_add_comment "$post_id" "$comment_json"
            ;;
        "feed:stats")
            feed_get_stats
            ;;
        "feed:display")
            local page="${1:-1}"
            local page_size="${2:-20}"
            get_feed_display "$page" "$page_size"
            ;;
        "feed:post-details")
            local post_id="$1"
            get_post_details "$post_id"
            ;;
        "feed:search-display")
            local query="$1"
            local page="${2:-1}"
            local page_size="${3:-20}"
            search_feed "$query" "$page" "$page_size"
            ;;
        "feed:user-feed")
            local user_id="$1"
            local page="${2:-1}"
            local page_size="${3:-20}"
            get_user_feed "$user_id" "$page" "$page_size"
            ;;
        "feed:statistics")
            get_feed_statistics
            ;;
        
        # Queue commands
        "queue:init")
            queue_init
            ;;
        "queue:enqueue")
            local event_json="$1"
            queue_enqueue "$event_json"
            ;;
        "queue:dequeue")
            queue_dequeue
            ;;
        "queue:peek")
            queue_peek
            ;;
        "queue:peek-rear")
            queue_peek_rear
            ;;
        "queue:get-all")
            local limit="${1:-0}"
            queue_get_all "$limit"
            ;;
        "queue:by-type")
            local event_type="$1"
            queue_get_by_type "$event_type"
            ;;
        "queue:by-priority")
            local priority="$1"
            queue_get_by_priority "$priority"
            ;;
        "queue:remove")
            local event_id="$1"
            queue_remove_event "$event_id"
            ;;
        "queue:clear")
            queue_clear
            ;;
        "queue:stats")
            queue_get_stats
            ;;
        "queue:validate")
            validate_queue
            ;;
        
        # Priority Queue commands
        "pqueue:init")
            pqueue_init
            ;;
        "pqueue:enqueue")
            local event_json="$1"
            pqueue_enqueue "$event_json"
            ;;
        "pqueue:dequeue")
            pqueue_dequeue
            ;;
        "pqueue:peek")
            pqueue_peek
            ;;
        "pqueue:get-all")
            pqueue_get_all
            ;;
        "pqueue:size-by-priority")
            pqueue_size_by_priority
            ;;
        "pqueue:clear")
            pqueue_clear
            ;;
        "pqueue:stats")
            pqueue_get_stats
            ;;
        
        # User commands
        "user:init")
            users_init
            ;;
        "user:create")
            local username="$1"
            create_user "$username"
            ;;
        "user:get")
            local user_id="$1"
            get_user "$user_id"
            ;;
        "user:get-by-username")
            local username="$1"
            get_user_by_username "$username"
            ;;
        "user:get-all")
            local limit="${1:-0}"
            get_all_users "$limit"
            ;;
        "user:random")
            get_random_user
            ;;
        "user:update-stats")
            local user_id="$1"
            local field="$2"
            local increment="${3:-1}"
            update_user_stats "$user_id" "$field" "$increment"
            ;;
        "user:search")
            local query="$1"
            search_users "$query"
            ;;
        "user:count")
            get_user_count
            ;;
        "user:validate")
            local user_json="$1"
            validate_user "$user_json"
            ;;
        "user:exists")
            local user_id="$1"
            user_exists "$user_id"
            ;;
        
        # Event commands
        "event:create")
            local user_id="$1"
            local user_name="$2"
            local event_type="$3"
            local content="$4"
            local target_post="$5"
            local target_user="$6"
            local priority="$7"
            create_event "$user_id" "$user_name" "$event_type" "$content" "$target_post" "$target_user" "$priority"
            ;;
        "event:post")
            local user_id="$1"
            local user_name="$2"
            local content="$3"
            local priority="${4:-$PRIORITY_POST}"
            create_post_event "$user_id" "$user_name" "$content" "$priority"
            ;;
        "event:like")
            local user_id="$1"
            local user_name="$2"
            local target_post="$3"
            local priority="${4:-$PRIORITY_LIKE}"
            create_like_event "$user_id" "$user_name" "$target_post" "$priority"
            ;;
        "event:comment")
            local user_id="$1"
            local user_name="$2"
            local target_post="$3"
            local content="$4"
            local priority="${5:-$PRIORITY_COMMENT}"
            create_comment_event "$user_id" "$user_name" "$target_post" "$content" "$priority"
            ;;
        "event:share")
            local user_id="$1"
            local user_name="$2"
            local target_post="$3"
            local priority="${4:-$PRIORITY_SHARE}"
            create_share_event "$user_id" "$user_name" "$target_post" "$priority"
            ;;
        "event:follow")
            local user_id="$1"
            local user_name="$2"
            local target_user="$3"
            local priority="${4:-$PRIORITY_FOLLOW}"
            create_follow_event "$user_id" "$user_name" "$target_user" "$priority"
            ;;
        "event:notification")
            local user_id="$1"
            local user_name="$2"
            local content="$3"
            local priority="${4:-$PRIORITY_NOTIFICATION}"
            create_notification_event "$user_id" "$user_name" "$content" "$priority"
            ;;
        "event:get")
            local event_id="$1"
            get_event "$event_id"
            ;;
        "event:update-status")
            local event_id="$1"
            local status="$2"
            update_event_status "$event_id" "$status"
            ;;
        "event:queue")
            local event_json="$1"
            local use_priority="${2:-false}"
            queue_event "$event_json" "$use_priority"
            ;;
        "event:process")
            local event_json="$1"
            process_event "$event_json"
            ;;
        "event:recent")
            local limit="${1:-50}"
            local event_type="${2:-}"
            get_recent_events "$limit" "$event_type"
            ;;
        "event:validate")
            local event_json="$1"
            validate_event "$event_json"
            ;;
        
        # Statistics commands
        "stats:init")
            stats_init
            ;;
        "stats:increment")
            local field="$1"
            local increment="${2:-1}"
            stats_increment "$field" "$increment"
            ;;
        "stats:decrement")
            local field="$1"
            local decrement="${2:-1}"
            stats_decrement "$field" "$decrement"
            ;;
        "stats:set")
            local field="$1"
            local value="$2"
            stats_set "$field" "$value"
            ;;
        "stats:get")
            local field="$1"
            stats_get "$field"
            ;;
        "stats:get-all")
            stats_get_all
            ;;
        "stats:display")
            stats_get_display
            ;;
        "stats:reset")
            stats_reset
            ;;
        "stats:update-uptime")
            stats_update_uptime
            ;;
        "stats:update-pending")
            stats_update_pending
            ;;
        
        # Process Manager commands
        "proc:init")
            manager_init
            ;;
        "proc:start-producer")
            local name="${1:-}"
            start_producer "$name"
            ;;
        "proc:start-worker")
            local name="${1:-}"
            start_worker "$name"
            ;;
        "proc:stop-producer")
            local name="$1"
            stop_producer "$name"
            ;;
        "proc:stop-worker")
            local name="$1"
            stop_worker "$name"
            ;;
        "proc:stop-all-producers")
            stop_all_producers
            ;;
        "proc:stop-all-workers")
            stop_all_workers
            ;;
        "proc:list-producers")
            list_producers
            ;;
        "proc:list-workers")
            list_workers
            ;;
        "proc:list-all")
            list_all_processes
            ;;
        "proc:monitor")
            monitor_processes
            ;;
        
        # System Manager commands
        "sys:start")
            local producers="${1:-$DEFAULT_PRODUCERS}"
            local workers="${2:-$DEFAULT_WORKERS}"
            system_start "$producers" "$workers"
            ;;
        "sys:stop")
            system_stop
            ;;
        "sys:restart")
            system_restart "$@"
            ;;
        "sys:status")
            system_status
            ;;
        "sys:scale-producers")
            local target="$1"
            scale_producers "$target"
            ;;
        "sys:scale-workers")
            local target="$1"
            scale_workers "$target"
            ;;
        "sys:health")
            system_health
            ;;
        
        # Resource Monitor commands
        "res:cpu")
            get_cpu_usage
            ;;
        "res:memory")
            get_memory_usage
            ;;
        "res:disk")
            local path="${1:-/}"
            get_disk_usage "$path"
            ;;
        "res:uptime")
            get_system_uptime
            ;;
        "res:processes")
            get_process_count
            ;;
        "res:load")
            get_load_average
            ;;
        "res:network")
            get_network_stats
            ;;
        "res:all")
            get_all_resources
            ;;
        "res:check")
            resource_check
            ;;
        
        # Cleanup commands
        "cleanup:all")
            cleanup_all
            ;;
        "cleanup:processes")
            cleanup_processes
            ;;
        "cleanup:pids")
            cleanup_pids
            ;;
        "cleanup:logs")
            local days="${1:-7}"
            cleanup_old_logs "$days"
            ;;
        "cleanup:events")
            local days="${1:-30}"
            cleanup_old_events "$days"
            ;;
        "cleanup:posts")
            local days="${1:-90}"
            cleanup_old_posts "$days"
            ;;
        "cleanup:queue")
            cleanup_queue
            ;;
        "cleanup:emergency")
            cleanup_emergency
            ;;
        "cleanup:prestart")
            cleanup_prestart
            ;;
        "cleanup:save")
            save_state
            ;;
        "cleanup:restore")
            restore_state
            ;;
        
        # Validation commands
        "validate:post")
            local post_json="$1"
            validate_post "$post_json"
            ;;
        "validate:feed")
            validate_feed
            ;;
        "validate:queue")
            validate_queue
            ;;
        "validate:all")
            validate_all_data
            ;;
        "validate:structure")
            validate_data_structure
            ;;
        
        # Log commands
        "log:events")
            local lines="${1:-50}"
            show_logs "EVENT" "$lines"
            ;;
        "log:workers")
            local lines="${1:-50}"
            show_logs "WORKER" "$lines"
            ;;
        "log:system")
            local lines="${1:-50}"
            show_logs "SYSTEM" "$lines"
            ;;
        "log:rotate")
            local max_lines="${1:-10000}"
            rotate_logs "$max_lines"
            ;;
        "log:clear")
            clear_logs
            ;;
        
        # Lock commands
        "lock:acquire")
            local lock_name="$1"
            local timeout="${2:-10}"
            lock_acquire "$lock_name" "$timeout"
            ;;
        "lock:release")
            local lock_name="$1"
            lock_release "$lock_name"
            ;;
        "lock:with")
            local lock_name="$1"
            shift
            with_lock "$lock_name" "$@"
            ;;
        "lock:try")
            local lock_name="$1"
            lock_try "$lock_name"
            ;;
        "lock:held")
            local lock_name="$1"
            lock_is_held "$lock_name"
            ;;
        "lock:info")
            local lock_name="$1"
            lock_info "$lock_name"
            ;;
        "lock:list")
            lock_list
            ;;
        "lock:force-release")
            local lock_name="$1"
            lock_force_release "$lock_name"
            ;;
        "lock:cleanup")
            lock_cleanup_all
            ;;
        
        # FIFO commands
        "fifo:create")
            fifo_create_all
            ;;
        "fifo:remove")
            fifo_remove_all
            ;;
        "fifo:write")
            local fifo_path="$1"
            local message="$2"
            local timeout="${3:-5}"
            fifo_write "$fifo_path" "$message" "$timeout"
            ;;
        "fifo:read")
            local fifo_path="$1"
            fifo_read "$fifo_path"
            ;;
        "fifo:read-timeout")
            local fifo_path="$1"
            local timeout="${2:-1}"
            fifo_read_timeout "$fifo_path" "$timeout"
            ;;
        
        help|--help|-h)
            show_help
            ;;
        *)
            echo "Unknown command: $cmd"
            show_help
            exit 1
            ;;
    esac
}

show_help() {
    cat << 'EOF'
Backend CLI - Real-Time Social Media Feed

Usage: backend_cli.sh <command> [args...]

Feed Commands:
  feed:init                 Initialize feed
  feed:add <post_json>      Add post to feed
  feed:remove <post_id>     Remove post from feed
  feed:update <post_id> <updates_json>  Update post
  feed:find <post_id>       Find post by ID
  feed:search <query>       Search posts by content
  feed:search-user <user_id> Search posts by user
  feed:get-all [limit]      Get all posts
  feed:page <page> <size>   Get paginated posts
  feed:like <post_id>       Increment likes
  feed:unlike <post_id>     Decrement likes
  feed:comment-inc <post_id> Increment comments
  feed:share-inc <post_id>  Increment shares
  feed:comment-add <post_id> <comment_json> Add comment
  feed:stats                Get feed statistics
  feed:display <page> <size> Get feed for display
  feed:post-details <post_id> Get single post
  feed:search-display <query> <page> <size> Search with pagination
  feed:user-feed <user_id> <page> <size> Get user's posts
  feed:statistics           Get combined statistics

Queue Commands:
  queue:init                Initialize queue
  queue:enqueue <event_json> Enqueue event
  queue:dequeue             Dequeue event
  queue:peek                Peek front event
  queue:peek-rear           Peek rear event
  queue:get-all [limit]     Get all events
  queue:by-type <type>      Get events by type
  queue:by-priority <pri>   Get events by priority
  queue:remove <event_id>   Remove specific event
  queue:clear               Clear queue
  queue:stats               Get queue statistics
  queue:validate            Validate queue integrity

Priority Queue Commands:
  pqueue:init               Initialize priority queue
  pqueue:enqueue <event_json> Enqueue with priority
  pqueue:dequeue            Dequeue highest priority
  pqueue:peek               Peek highest priority
  pqueue:get-all            Get all grouped by priority
  pqueue:size-by-priority   Get size per priority
  pqueue:clear              Clear priority queue
  pqueue:stats              Get priority queue statistics

User Commands:
  user:init                 Initialize users
  user:create <username>    Create user
  user:get <user_id>        Get user by ID
  user:get-by-username <name> Get user by username
  user:get-all [limit]      Get all users
  user:random               Get random user
  user:update-stats <id> <field> [inc] Update user stats
  user:search <query>       Search users
  user:count                Get user count
  user:validate <json>      Validate user object
  user:exists <user_id>     Check if user exists

Event Commands:
  event:create <user_id> <user_name> <type> <content> <target_post> <target_user> <priority> Create event
  event:post <user_id> <user_name> <content> [priority] Create POST event
  event:like <user_id> <user_name> <target_post> [priority] Create LIKE event
  event:comment <user_id> <user_name> <target_post> <content> [priority] Create COMMENT event
  event:share <user_id> <user_name> <target_post> [priority] Create SHARE event
  event:follow <user_id> <user_name> <target_user> [priority] Create FOLLOW event
  event:notification <user_id> <user_name> <content> [priority] Create NOTIFICATION event
  event:get <event_id>      Get event by ID
  event:update-status <id> <status> Update event status
  event:queue <event_json> [use_priority] Queue event for processing
  event:process <event_json> Process event
  event:recent [limit] [type] Get recent events
  event:validate <json>     Validate event object

Statistics Commands:
  stats:init                Initialize statistics
  stats:increment <field> [inc] Increment counter
  stats:decrement <field> [dec] Decrement counter
  stats:set <field> <value> Set gauge value
  stats:get <field>         Get statistic
  stats:get-all             Get all statistics
  stats:display             Get formatted display
  stats:reset               Reset all statistics
  stats:update-uptime       Update uptime
  stats:update-pending      Update pending count

Process Commands:
  proc:start-producer [name] Start producer
  proc:start-worker [name]   Start worker
  proc:stop-producer <name>  Stop producer
  proc:stop-worker <name>    Stop worker
  proc:stop-all-producers    Stop all producers
  proc:stop-all-workers      Stop all workers
  proc:list-producers        List producers
  proc:list-workers          List workers
  proc:list-all              List all processes
  proc:monitor               Monitor and restart dead processes

System Commands:
  sys:start [producers] [workers] Start system
  sys:stop                        Stop system
  sys:restart [producers] [workers] Restart system
  sys:status                      System status
  sys:scale-producers <target>    Scale producers
  sys:scale-workers <target>      Scale workers
  sys:health                      Health check

Resource Commands:
  res:cpu               CPU usage %
  res:memory            Memory usage
  res:disk [path]       Disk usage
  res:uptime            System uptime
  res:processes         Process count
  res:load              Load average
  res:network           Network stats
  res:all               All resources

Cleanup Commands:
  cleanup:all           Full cleanup
  cleanup:processes     Stop all processes
  cleanup:pids          Remove PID files
  cleanup:logs [days]   Clean old logs
  cleanup:events [days] Clean old events
  cleanup:posts [days]  Clean old posts
  cleanup:queue         Clear queues
  cleanup:emergency     Emergency cleanup
  cleanup:prestart      Pre-start cleanup
  cleanup:save          Save state
  cleanup:restore       Restore state

Validation Commands:
  validate:post <json>     Validate post
  validate:feed            Validate feed
  validate:queue           Validate queue
  validate:all             Validate all data
  validate:structure       Validate directory structure

Log Commands:
  log:events [lines]    Show event logs
  log:workers [lines]   Show worker logs
  log:system [lines]    Show system logs
  log:rotate [max]      Rotate logs
  log:clear             Clear all logs

Lock Commands:
  lock:acquire <name> [timeout] Acquire lock
  lock:release <name>   Release lock
  lock:with <name> <cmd> [args] Execute with lock
  lock:try <name>       Try acquire (non-blocking)
  lock:held <name>      Check if held
  lock:info <name>      Lock info
  lock:list             List all locks
  lock:force-release <name> Force release
  lock:cleanup          Cleanup all locks

FIFO Commands:
  fifo:create           Create all FIFOs
  fifo:remove           Remove all FIFOs
  fifo:write <path> <msg> [timeout] Write to FIFO
  fifo:read <path>      Read from FIFO (blocking)
  fifo:read-timeout <path> [timeout] Read with timeout

Examples:
  ./backend_cli.sh feed:display 1 20
  ./backend_cli.sh queue:stats
  ./backend_cli.sh stats:display
  ./backend_cli.sh sys:status
  ./backend_cli.sh res:all
EOF
}

main "$@"
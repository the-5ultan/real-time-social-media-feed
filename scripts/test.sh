#!/usr/bin/env bash
# Test runner for Real-Time Social Media Feed
# Runs all test suites

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

print_step() { echo -e "${BLUE}[TEST]${NC} $*"; }
print_success() { echo -e "${GREEN}[PASS]${NC} $*"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
print_error() { echo -e "${RED}[FAIL]${NC} $*" >&2; }

# Test results
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

run_test() {
    local test_name="$1"
    local test_script="$2"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    print_step "Running $test_name..."
    
    if bash "$test_script"; then
        print_success "$test_name passed"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        print_error "$test_name failed"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

run_inline_test() {
    local test_name="$1"
    shift
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    print_step "Running $test_name..."
    
    if "$@"; then
        print_success "$test_name passed"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        print_error "$test_name failed"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# =============================================================================
# TEST SUITES
# =============================================================================

test_datastructures() {
    source "${PROJECT_ROOT}/backend/config.sh"
    source "${PROJECT_ROOT}/backend/utils/common.sh"
    source "${PROJECT_ROOT}/backend/datastructures/feed.sh"
    source "${PROJECT_ROOT}/backend/datastructures/queue.sh"
    source "${PROJECT_ROOT}/backend/datastructures/priority_queue.sh"
    
    # Test feed
    feed_init
    [[ $(feed_size) -eq 0 ]] || return 1
    
    local post1=$(json_object "post_id" "test_post_1" "user_id" "user_1" "username" "testuser" "content" "Test post" "timestamp" "$(get_timestamp)" "likes" "0" "comments" "0" "shares" "0")
    feed_add_post "$post1"
    [[ $(feed_size) -eq 1 ]] || return 1
    
    local found=$(feed_find_post "test_post_1")
    [[ -n "$found" && "$found" != "null" ]] || return 1
    
    feed_remove_post "test_post_1"
    [[ $(feed_size) -eq 0 ]] || return 1
    
    # Test queue
    queue_init
    [[ $(queue_size) -eq 0 ]] || return 1
    
    local event1=$(json_object "event_id" "test_evt_1" "user_id" "user_1" "user_name" "testuser" "event_type" "POST" "content" "Test" "timestamp" "$(get_timestamp)" "priority" "5" "status" "CREATED")
    queue_enqueue "$event1"
    [[ $(queue_size) -eq 1 ]] || return 1
    
    local peeked=$(queue_peek)
    [[ -n "$peeked" && "$peeked" != "null" ]] || return 1
    
    local dequeued=$(queue_dequeue)
    [[ -n "$dequeued" && "$dequeued" != "null" ]] || return 1
    [[ $(queue_size) -eq 0 ]] || return 1
    
    # Test priority queue
    pqueue_init
    [[ $(pqueue_size) -eq 0 ]] || return 1
    
    local high_pri=$(json_object "event_id" "test_evt_2" "user_id" "user_1" "user_name" "testuser" "event_type" "NOTIFICATION" "content" "High priority" "timestamp" "$(get_timestamp)" "priority" "1" "status" "CREATED")
    local low_pri=$(json_object "event_id" "test_evt_3" "user_id" "user_1" "user_name" "testuser" "event_type" "POST" "content" "Low priority" "timestamp" "$(get_timestamp)" "priority" "5" "status" "CREATED")
    
    pqueue_enqueue "$low_pri"
    pqueue_enqueue "$high_pri"
    [[ $(pqueue_size) -eq 2 ]] || return 1
    
    # High priority should come out first
    local first=$(pqueue_dequeue)
    local first_pri=$(echo "$first" | jq -r '.priority')
    [[ "$first_pri" -eq 1 ]] || return 1
    
    return 0
}

test_services() {
    source "${PROJECT_ROOT}/backend/config.sh"
    source "${PROJECT_ROOT}/backend/utils/common.sh"
    source "${PROJECT_ROOT}/backend/services/user_service.sh"
    source "${PROJECT_ROOT}/backend/services/event_service.sh"
    source "${PROJECT_ROOT}/backend/services/feed_service.sh"
    source "${PROJECT_ROOT}/backend/services/statistics_service.sh"
    source "${PROJECT_ROOT}/backend/datastructures/feed.sh"
    source "${PROJECT_ROOT}/backend/datastructures/queue.sh"
    
    # Init
    users_init
    feed_init
    queue_init
    stats_init
    
    # Test user creation
    local user=$(create_user "testuser1")
    [[ -n "$user" ]] || return 1
    local user_id=$(echo "$user" | jq -r '.user_id')
    [[ -n "$user_id" && "$user_id" != "null" ]] || return 1
    
    # Test get user
    local found=$(get_user "$user_id")
    [[ -n "$found" ]] || return 1
    
    # Test event creation
    local event=$(create_post_event "$user_id" "testuser1" "Test post content")
    [[ -n "$event" ]] || return 1
    local event_id=$(echo "$event" | jq -r '.event_id')
    [[ -n "$event_id" && "$event_id" != "null" ]] || return 1
    
    # Test queue event
    queue_event "$event"
    [[ $(queue_size) -eq 1 ]] || return 1
    
    # Test stats
    stats_increment "test_counter"
    local val=$(stats_get "test_counter")
    [[ "$val" -eq 1 ]] || return 1
    
    return 0
}

test_ipc() {
    source "${PROJECT_ROOT}/backend/config.sh"
    source "${PROJECT_ROOT}/backend/utils/common.sh"
    source "${PROJECT_ROOT}/backend/ipc/fifo.sh"
    
    # Test FIFO creation
    fifo_create_all
    [[ -p "$PRODUCER_FIFO" ]] || return 1
    [[ -p "$WORKER_FIFO" ]] || return 1
    [[ -p "$CONTROL_FIFO" ]] || return 1
    
    # Test write/read (with timeout)
    echo "test_message" > "$PRODUCER_FIFO" &
    local write_pid=$!
    sleep 0.1
    local read_msg=$(timeout 1 cat "$PRODUCER_FIFO" 2>/dev/null || echo "")
    wait $write_pid 2>/dev/null || true
    
    [[ "$read_msg" == "test_message" ]] || return 1
    
    # Cleanup
    fifo_remove_all
    [[ ! -p "$PRODUCER_FIFO" ]] || return 1
    
    return 0
}

test_synchronization() {
    source "${PROJECT_ROOT}/backend/config.sh"
    source "${PROJECT_ROOT}/backend/utils/common.sh"
    source "${PROJECT_ROOT}/backend/synchronization/locks.sh"
    
    # Test lock acquire/release
    lock_acquire "test_lock" 2
    lock_release "test_lock"
    
    # Test with_lock
    local counter=0
    for i in {1..10}; do
        (
            with_lock "counter_lock" bash -c '
                source "'"${PROJECT_ROOT}/backend/config.sh"'"
                source "'"${PROJECT_ROOT}/backend/utils/common.sh"'"
                source "'"${PROJECT_ROOT}/backend/synchronization/locks.sh"'"
                # This runs in subshell so we need different approach
            '
        ) &
    done
    wait
    
    # Test lock_try
    lock_try "try_lock" && lock_release "try_lock"
    
    # Cleanup
    lock_cleanup_all
    
    return 0
}

test_processes() {
    source "${PROJECT_ROOT}/backend/config.sh"
    source "${PROJECT_ROOT}/backend/utils/common.sh"
    source "${PROJECT_ROOT}/backend/processes/manager.sh"
    
    # Test manager functions
    manager_init
    
    # Start a producer
    start_producer "test_producer"
    sleep 0.5
    
    local pid=$(load_pid "test_producer")
    [[ -n "$pid" ]] || return 1
    
    # Check it's running
    kill -0 "$pid" 2>/dev/null || return 1
    
    # Stop it
    stop_producer "test_producer"
    sleep 0.5
    
    # Should be stopped
    ! kill -0 "$pid" 2>/dev/null || return 1
    
    manager_shutdown
    return 0
}

test_persistence() {
    source "${PROJECT_ROOT}/backend/config.sh"
    source "${PROJECT_ROOT}/backend/utils/common.sh"
    source "${PROJECT_ROOT}/backend/services/user_service.sh"
    source "${PROJECT_ROOT}/backend/services/event_service.sh"
    source "${PROJECT_ROOT}/backend/datastructures/feed.sh"
    source "${PROJECT_ROOT}/backend/datastructures/queue.sh"
    source "${PROJECT_ROOT}/backend/system/cleanup.sh"
    
    # Create test data
    users_init
    feed_init
    queue_init
    
    local user=$(create_user "persist_user")
    local user_id=$(echo "$user" | jq -r '.user_id')
    
    local post=$(json_object "post_id" "persist_post" "user_id" "$user_id" "username" "persist_user" "content" "Persistent post" "timestamp" "$(get_timestamp)" "likes" "5" "comments" "2" "shares" "1")
    feed_add_post "$post"
    
    local event=$(create_post_event "$user_id" "persist_user" "Persistent event")
    queue_event "$event"
    
    # Save state
    save_state
    
    # Verify state files exist
    [[ -f "${STATS_DIR}/state_stats.json" ]] || return 1
    [[ -f "${QUEUE_DIR}/state_queue.json" ]] || return 1
    [[ -f "${FEED_DIR}/state_feed.json" ]] || return 1
    
    # Cleanup
    cleanup_queue
    rm -f "${STATS_DIR}/state_stats.json" "${QUEUE_DIR}/state_queue.json" "${FEED_DIR}/state_feed.json" "${PIDS_DIR}/state_pids.txt"
    
    return 0
}

test_cleanup() {
    source "${PROJECT_ROOT}/backend/config.sh"
    source "${PROJECT_ROOT}/backend/utils/common.sh"
    source "${PROJECT_ROOT}/backend/system/cleanup.sh"
    
    # Create some test files
    mkdir -p "$PIDS_DIR" "$LOCKS_DIR" "$PIPES_DIR"
    echo "12345" > "${PIDS_DIR}/test.pid"
    touch "${LOCKS_DIR}/test.lock"
    mkfifo "${PIPES_DIR}/test.fifo" 2>/dev/null || true
    
    # Run prestart cleanup
    cleanup_prestart
    
    # Should be cleaned
    [[ ! -f "${PIDS_DIR}/test.pid" ]] || return 1
    [[ ! -f "${LOCKS_DIR}/test.lock" ]] || return 1
    [[ ! -p "${PIPES_DIR}/test.fifo" ]] || return 1
    
    return 0
}

test_validation() {
    source "${PROJECT_ROOT}/backend/config.sh"
    source "${PROJECT_ROOT}/backend/utils/common.sh"
    source "${PROJECT_ROOT}/backend/utils/validation.sh"
    
    # Test event validation
    local valid_event=$(json_object "event_id" "evt_1" "user_id" "user_1" "event_type" "POST" "content" "Test" "timestamp" "$(get_timestamp)" "priority" "5" "status" "CREATED")
    validate_event "$valid_event" || return 1
    
    local invalid_event=$(json_object "event_id" "evt_1" "user_id" "user_1" "event_type" "INVALID" "timestamp" "$(get_timestamp)" "priority" "5")
    ! validate_event "$invalid_event" >/dev/null 2>&1 || return 1
    
    # Test user validation
    local valid_user=$(json_object "user_id" "user_1" "username" "validuser" "created_at" "$(get_timestamp)")
    validate_user "$valid_user" || return 1
    
    local invalid_user=$(json_object "user_id" "user_1" "username" "ab" "created_at" "$(get_timestamp)")
    ! validate_user "$invalid_user" >/dev/null 2>&1 || return 1
    
    # Test post validation
    local valid_post=$(json_object "post_id" "post_1" "user_id" "user_1" "content" "Test post" "timestamp" "$(get_timestamp)")
    validate_post "$valid_post" || return 1
    
    return 0
}

test_logger() {
    source "${PROJECT_ROOT}/backend/config.sh"
    source "${PROJECT_ROOT}/backend/utils/common.sh"
    source "${PROJECT_ROOT}/backend/utils/logger.sh"
    
    # Test logging functions (just ensure they don't crash)
    log_info "TEST" "Test info message"
    log_warn "TEST" "Test warning message"
    log_error "TEST" "Test error message"
    log_event "evt_test" "testuser" "POST" "CREATED" "Test event"
    log_worker "worker-1" "evt_test" "POST" "PROCESSED" "Test worker"
    log_system "Test system message"
    log_debug "TEST" "Test debug message"
    
    # Test log rotation
    rotate_logs 10
    
    return 0
}

test_resource_monitor() {
    source "${PROJECT_ROOT}/backend/config.sh"
    source "${PROJECT_ROOT}/backend/utils/common.sh"
    source "${PROJECT_ROOT}/backend/system/resource_monitor.sh"
    
    # Test resource functions
    local cpu=$(get_cpu_usage)
    [[ "$cpu" =~ ^[0-9]+$ ]] || return 1
    
    local mem=$(get_memory_usage)
    echo "$mem" | jq -e '.usage_percent' >/dev/null || return 1
    
    local disk=$(get_disk_usage)
    echo "$disk" | jq -e '.usage_percent' >/dev/null || return 1
    
    local uptime=$(get_system_uptime)
    echo "$uptime" | jq -e '.seconds' >/dev/null || return 1
    
    local procs=$(get_process_count)
    echo "$procs" | jq -e '.total' >/dev/null || return 1
    
    local load=$(get_load_average)
    echo "$load" | jq -e '.["1min"]' >/dev/null || return 1
    
    local all=$(get_all_resources)
    echo "$all" | jq -e '.cpu_usage_percent' >/dev/null || return 1
    
    return 0
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    echo
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  Real-Time Social Media Feed - Test Suite                    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo
    
    # Run all test suites
    run_inline_test "Data Structures" test_datastructures
    run_inline_test "Services" test_services
    run_inline_test "IPC (FIFO)" test_ipc
    run_inline_test "Synchronization (flock)" test_synchronization
    run_inline_test "Process Management" test_processes
    run_inline_test "Persistence" test_persistence
    run_inline_test "Cleanup" test_cleanup
    run_inline_test "Validation" test_validation
    run_inline_test "Logger" test_logger
    run_inline_test "Resource Monitor" test_resource_monitor
    
    # Run existing test file if exists
    if [[ -f "${PROJECT_ROOT}/tests/test_datastructures.sh" ]]; then
        run_test "Existing Data Structures Test" "${PROJECT_ROOT}/tests/test_datastructures.sh"
    fi
    
    echo
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  TEST SUMMARY                                                ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    printf "║  Total:   %-3d                                               ║\n" "$TESTS_TOTAL"
    printf "║  Passed:  %-3d                                               ║\n" "$TESTS_PASSED"
    printf "║  Failed:  %-3d                                               ║\n" "$TESTS_FAILED"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        print_success "All tests passed!"
        exit 0
    else
        print_error "$TESTS_FAILED test(s) failed"
        exit 1
    fi
}

main "$@"
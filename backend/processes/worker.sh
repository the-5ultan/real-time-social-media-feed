#!/usr/bin/env bash
# Worker Process
# Consumes events from queue and processes them

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
source "${PROJECT_ROOT}/backend/services/statistics_service.sh"

# =============================================================================
# WORKER CONFIGURATION
# =============================================================================

WORKER_ID="${1:-worker-$$}"
WORKER_POLL_INTERVAL="${WORKER_POLL_INTERVAL:-0.5}"
USE_PRIORITY_QUEUE="${USE_PRIORITY_QUEUE:-false}"
EVENTS_PROCESSED=0

# =============================================================================
# WORKER FUNCTIONS
# =============================================================================

# Initialize worker
worker_init() {
    log_worker "$WORKER_ID" "" "" "Worker initialized" "$$"
    stats_increment "active_workers"
    
    # Setup signal handlers
    trap 'worker_shutdown' EXIT INT TERM
}

# Shutdown worker
worker_shutdown() {
    log_worker "$WORKER_ID" "" "" "Worker shutting down (processed: $EVENTS_PROCESSED events)" "$$"
    stats_decrement "active_workers"
}

# Process single event
worker_process_event() {
    local event_json="$1"
    local event_id=$(json_get "$event_json" "event_id")
    local event_type=$(json_get "$event_json" "event_type")
    
    log_worker "$WORKER_ID" "$event_id" "$event_type" "$STATUS_PROCESSING" "Processing event"
    
    # Process the event
    process_event "$event_json"
    
    ((EVENTS_PROCESSED++))
    stats_increment "processed_events"
    
    log_worker "$WORKER_ID" "$event_id" "$event_type" "$STATUS_PROCESSED" "Event processed (total: $EVENTS_PROCESSED)"
}

# Main worker loop
worker_run() {
    log_worker "$WORKER_ID" "" "" "Worker started, poll interval: ${WORKER_POLL_INTERVAL}s" "$$"
    
    while true; do
        local event_json=""
        
        # Dequeue event
        if [[ "$USE_PRIORITY_QUEUE" == "true" ]]; then
            event_json=$(pqueue_dequeue)
        else
            event_json=$(queue_dequeue)
        fi
        
        if [[ -n "$event_json" && "$event_json" != "null" ]]; then
            worker_process_event "$event_json"
        else
            # Queue empty, sleep before next poll
            sleep "$WORKER_POLL_INTERVAL"
        fi
    done
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    worker_init
    worker_run
}

main "$@"
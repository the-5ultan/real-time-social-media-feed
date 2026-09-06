#!/usr/bin/env bash
# Configuration for Real-Time Social Media Feed
# This file contains all configurable parameters for the system

# Prevent multiple sourcing
[[ -n "${CONFIG_LOADED:-}" ]] && return 0
readonly CONFIG_LOADED=1

# =============================================================================
# SYSTEM PATHS
# =============================================================================

# Base directory (auto-detected)
readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Data directories
readonly DATA_DIR="${PROJECT_ROOT}/data"
readonly USERS_DIR="${DATA_DIR}/users"
readonly POSTS_DIR="${DATA_DIR}/posts"
readonly EVENTS_DIR="${DATA_DIR}/events"
readonly FEED_DIR="${DATA_DIR}/feed"
readonly QUEUE_DIR="${DATA_DIR}/queue"
readonly STATS_DIR="${DATA_DIR}/stats"

# Log directories
readonly LOGS_DIR="${PROJECT_ROOT}/logs"
readonly EVENTS_LOG="${LOGS_DIR}/events.log"
readonly WORKERS_LOG="${LOGS_DIR}/workers.log"
readonly SYSTEM_LOG="${LOGS_DIR}/system.log"

# Runtime directories
readonly RUNTIME_DIR="${PROJECT_ROOT}/runtime"
readonly PIDS_DIR="${RUNTIME_DIR}/pids"
readonly LOCKS_DIR="${RUNTIME_DIR}/locks"
readonly PIPES_DIR="${RUNTIME_DIR}/pipes"

# =============================================================================
# PROCESS CONFIGURATION
# =============================================================================

# Default number of processes
readonly DEFAULT_PRODUCERS=3
readonly DEFAULT_WORKERS=2
readonly MAX_PRODUCERS=10
readonly MAX_WORKERS=10

# Process timing (seconds)
readonly PRODUCER_INTERVAL=2      # Time between event generations
readonly WORKER_POLL_INTERVAL=0.5 # Time between queue checks
readonly MANAGER_POLL_INTERVAL=1  # Process manager check interval

# =============================================================================
# QUEUE CONFIGURATION
# =============================================================================

# Queue files
readonly QUEUE_FILE="${QUEUE_DIR}/event_queue.json"
readonly QUEUE_LOCK="${LOCKS_DIR}/queue.lock"
readonly QUEUE_MAX_SIZE=10000

# Priority queue file
readonly PRIORITY_QUEUE_FILE="${QUEUE_DIR}/priority_queue.json"

# =============================================================================
# FEED CONFIGURATION
# =============================================================================

# Feed files
readonly FEED_FILE="${FEED_DIR}/feed.json"
readonly FEED_LOCK="${LOCKS_DIR}/feed.lock"
readonly FEED_MAX_POSTS=1000

# =============================================================================
# IPC CONFIGURATION
# =============================================================================

# FIFO pipes
readonly PRODUCER_FIFO="${PIPES_DIR}/producer.fifo"
readonly WORKER_FIFO="${PIPES_DIR}/worker.fifo"
readonly CONTROL_FIFO="${PIPES_DIR}/control.fifo"

# =============================================================================
# EVENT CONFIGURATION
# =============================================================================

# Event types
readonly EVENT_POST="POST"
readonly EVENT_LIKE="LIKE"
readonly EVENT_COMMENT="COMMENT"
readonly EVENT_SHARE="SHARE"
readonly EVENT_FOLLOW="FOLLOW"
readonly EVENT_NOTIFICATION="NOTIFICATION"

# Event priorities (lower = higher priority)
readonly PRIORITY_NOTIFICATION=1
readonly PRIORITY_COMMENT=2
readonly PRIORITY_SHARE=3
readonly PRIORITY_LIKE=4
readonly PRIORITY_POST=5
readonly PRIORITY_FOLLOW=6
readonly PRIORITY_DEFAULT=5

# Event statuses
readonly STATUS_CREATED="CREATED"
readonly STATUS_QUEUED="QUEUED"
readonly STATUS_PROCESSING="PROCESSING"
readonly STATUS_PROCESSED="PROCESSED"
readonly STATUS_FAILED="FAILED"

# =============================================================================
# USER CONFIGURATION
# =============================================================================

# Default users (auto-generated if not exist)
readonly DEFAULT_USERS=(
    "Ali"
    "Ahmed"
    "Sara"
    "Omar"
    "Layla"
    "Hassan"
    "Mona"
    "Karim"
)

# User files
readonly USERS_FILE="${USERS_DIR}/users.json"
readonly USERS_LOCK="${LOCKS_DIR}/users.lock"

# =============================================================================
# STATISTICS CONFIGURATION
# =============================================================================

# Statistics files
readonly STATS_FILE="${STATS_DIR}/statistics.json"
readonly STATS_LOCK="${LOCKS_DIR}/stats.lock"

# =============================================================================
# LOGGING CONFIGURATION
# =============================================================================

# Log levels
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3

# Default log level
readonly DEFAULT_LOG_LEVEL=${LOG_LEVEL_INFO}

# Log format: [TIMESTAMP] PID=xxx USER=xxx EVENT=xxx STATUS=xxx
readonly LOG_TIMESTAMP_FORMAT="%Y-%m-%d %H:%M:%S"

# =============================================================================
# SIMULATION CONFIGURATION
# =============================================================================

# Simulation mode
readonly SIMULATION_ENABLED=true
readonly SIMULATION_EVENT_BURST=10
readonly SIMULATION_DURATION=60

# =============================================================================
# FRONTEND CONFIGURATION
# =============================================================================

# Frontend polling interval (ms)
readonly FRONTEND_POLL_INTERVAL=1000

# =============================================================================
# RESOURCE MONITORING
# =============================================================================

# Resource monitor interval (seconds)
readonly RESOURCE_MONITOR_INTERVAL=5

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Ensure all directories exist
init_directories() {
    local dirs=(
        "${USERS_DIR}"
        "${POSTS_DIR}"
        "${EVENTS_DIR}"
        "${FEED_DIR}"
        "${QUEUE_DIR}"
        "${STATS_DIR}"
        "${LOGS_DIR}"
        "${PIDS_DIR}"
        "${LOCKS_DIR}"
        "${PIPES_DIR}"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "${dir}"
    done
}

# Get configuration value with fallback
get_config() {
    local key="$1"
    local default="$2"
    local value="${!key:-}"
    echo "${value:-$default}"
}

# Export all readonly variables for subprocesses
export PROJECT_ROOT DATA_DIR USERS_DIR POSTS_DIR EVENTS_DIR FEED_DIR QUEUE_DIR STATS_DIR
export LOGS_DIR EVENTS_LOG WORKERS_LOG SYSTEM_LOG
export RUNTIME_DIR PIDS_DIR LOCKS_DIR PIPES_DIR
export DEFAULT_PRODUCERS DEFAULT_WORKERS MAX_PRODUCERS MAX_WORKERS
export PRODUCER_INTERVAL WORKER_POLL_INTERVAL MANAGER_POLL_INTERVAL
export QUEUE_FILE QUEUE_LOCK QUEUE_MAX_SIZE PRIORITY_QUEUE_FILE
export FEED_FILE FEED_LOCK FEED_MAX_POSTS
export PRODUCER_FIFO WORKER_FIFO CONTROL_FIFO
export EVENT_POST EVENT_LIKE EVENT_COMMENT EVENT_SHARE EVENT_FOLLOW EVENT_NOTIFICATION
export PRIORITY_NOTIFICATION PRIORITY_COMMENT PRIORITY_SHARE PRIORITY_LIKE PRIORITY_POST PRIORITY_FOLLOW PRIORITY_DEFAULT
export STATUS_CREATED STATUS_QUEUED STATUS_PROCESSING STATUS_PROCESSED STATUS_FAILED
export USERS_FILE USERS_LOCK
export STATS_FILE STATS_LOCK
export DEFAULT_LOG_LEVEL LOG_TIMESTAMP_FORMAT
export SIMULATION_ENABLED SIMULATION_EVENT_BURST SIMULATION_DURATION
export FRONTEND_POLL_INTERVAL
export RESOURCE_MONITOR_INTERVAL
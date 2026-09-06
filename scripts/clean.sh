#!/usr/bin/env bash
# Clean script for Real-Time Social Media Feed
# Removes all generated data, logs, and runtime files

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

source "${PROJECT_ROOT}/backend/config.sh"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

print_step() { echo -e "${BLUE}[CLEAN]${NC} $*"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
print_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# =============================================================================
# CLEAN FUNCTIONS
# =============================================================================

confirm() {
    local prompt="$1"
    local default="${2:-N}"
    
    if [[ "$default" == "Y" ]]; then
        prompt+=" [Y/n]: "
    else
        prompt+=" [y/N]: "
    fi
    
    read -r -p "$prompt" response
    response=${response:-$default}
    [[ "$response" =~ ^[Yy]$ ]]
}

clean_data() {
    print_step "Cleaning data files..."
    
    # Users
    rm -f "${USERS_DIR}"/*.json
    rm -f "$USERS_FILE"
    
    # Posts
    rm -f "${POSTS_DIR}"/*.json
    
    # Events
    rm -f "${EVENTS_DIR}"/*.json
    
    # Feed
    rm -f "${FEED_DIR}"/*.json
    rm -f "$FEED_FILE"
    
    # Queue
    rm -f "${QUEUE_DIR}"/*.json
    rm -f "$QUEUE_FILE"
    rm -f "$PRIORITY_QUEUE_FILE"
    
    # Stats
    rm -f "${STATS_DIR}"/*.json
    rm -f "$STATS_FILE"
    
    print_success "Data files cleaned"
}

clean_logs() {
    print_step "Cleaning log files..."
    
    rm -f "$EVENTS_LOG"
    rm -f "$WORKERS_LOG"
    rm -f "$SYSTEM_LOG"
    rm -f "${LOGS_DIR}"/*.log.*
    
    print_success "Log files cleaned"
}

clean_runtime() {
    print_step "Cleaning runtime files..."
    
    # PIDs
    rm -f "${PIDS_DIR}"/*.pid
    
    # Locks
    rm -f "${LOCKS_DIR}"/*.lock
    
    # Pipes/FIFOs
    rm -f "${PIPES_DIR}"/*
    rm -f "$PRODUCER_FIFO" "$WORKER_FIFO" "$CONTROL_FIFO"
    
    print_success "Runtime files cleaned"
}

clean_frontend() {
    print_step "Cleaning frontend build artifacts..."
    
    rm -rf "${PROJECT_ROOT}/frontend/node_modules"
    rm -rf "${PROJECT_ROOT}/frontend/dist"
    rm -rf "${PROJECT_ROOT}/frontend/build"
    rm -rf "${PROJECT_ROOT}/frontend/.cache"
    
    print_success "Frontend artifacts cleaned"
}

clean_tests() {
    print_step "Cleaning test artifacts..."
    
    rm -rf "${PROJECT_ROOT}/tests/output"
    rm -f "${PROJECT_ROOT}/tests"/*.tmp
    
    print_success "Test artifacts cleaned"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    local force=false
    local clean_all=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                force=true
                shift
                ;;
            -a|--all)
                clean_all=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  -f, --force    Skip confirmation prompts"
                echo "  -a, --all      Clean everything including frontend node_modules"
                echo "  -h, --help     Show this help"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    echo
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  Real-Time Social Media Feed - Clean                         ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo
    
    # Stop system first if running
    if [[ -f "${PIDS_DIR}/manager.pid" ]] && kill -0 "$(cat "${PIDS_DIR}/manager.pid")" 2>/dev/null; then
        print_warn "System is running. Stopping first..."
        "${SCRIPT_DIR}/stop.sh"
    fi
    
    if [[ "$force" != "true" ]]; then
        echo "This will remove:"
        echo "  - All user data, posts, events, feed, queue, statistics"
        echo "  - All log files"
        echo "  - All runtime files (PIDs, locks, pipes)"
        [[ "$clean_all" == "true" ]] && echo "  - Frontend build artifacts (node_modules, dist, build)"
        echo
        confirm "Are you sure you want to continue?" || {
            print_warn "Clean cancelled"
            exit 0
        }
    fi
    
    clean_data
    clean_logs
    clean_runtime
    
    if [[ "$clean_all" == "true" ]]; then
        clean_frontend
        clean_tests
    fi
    
    # Recreate empty structure
    mkdir -p "$USERS_DIR" "$POSTS_DIR" "$EVENTS_DIR" "$FEED_DIR" "$QUEUE_DIR" "$STATS_DIR"
    mkdir -p "$LOGS_DIR" "$PIDS_DIR" "$LOCKS_DIR" "$PIPES_DIR"
    
    print_success "Clean completed"
    echo
    echo "Run ./scripts/setup.sh to reinitialize the system"
    echo
}

main "$@"
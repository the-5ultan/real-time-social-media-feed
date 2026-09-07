#!/usr/bin/env bash
# Stop script for Real-Time Social Media Feed
# Gracefully stops all system processes

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

source "${PROJECT_ROOT}/backend/config.sh"
source "${PROJECT_ROOT}/backend/utils/common.sh"
source "${PROJECT_ROOT}/backend/utils/logger.sh"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

print_step() { echo -e "${BLUE}[STOP]${NC} $*"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
print_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# =============================================================================
# STOP FUNCTIONS
# =============================================================================

stop_process_by_pidfile() {
    local name="$1"
    local pid_file="${PIDS_DIR}/${name}.pid"
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            print_step "Stopping $name (PID: $pid)..."
            kill -TERM "$pid" 2>/dev/null
            
            local count=0
            while kill -0 "$pid" 2>/dev/null && [[ $count -lt 10 ]]; do
                sleep 1
                ((count++))
            done
            
            if kill -0 "$pid" 2>/dev/null; then
                print_warn "Force killing $name (PID: $pid)..."
                kill -KILL "$pid" 2>/dev/null
                sleep 1
            fi
            
            print_success "Stopped $name"
        else
            print_warn "$name (PID: $pid) was not running"
        fi
        rm -f "$pid_file"
    fi
}

stop_all_processes() {
    print_step "Stopping all processes..."
    
    # Stop in reverse order: simulator, api_server, producers, workers, manager, monitor
    stop_process_by_pidfile "simulator"
    stop_process_by_pidfile "api_server"
    stop_process_by_pidfile "resource_monitor"
    
    # Stop all producers
    for pid_file in "${PIDS_DIR}"/producer-*.pid; do
        [[ -f "$pid_file" ]] || continue
        local name=$(basename "$pid_file" .pid)
        stop_process_by_pidfile "$name"
    done
    
    # Stop all workers
    for pid_file in "${PIDS_DIR}"/worker-*.pid; do
        [[ -f "$pid_file" ]] || continue
        local name=$(basename "$pid_file" .pid)
        stop_process_by_pidfile "$name"
    done
    
    stop_process_by_pidfile "manager"
    
    # Kill any remaining processes from our project
    pkill -f "backend/processes/" 2>/dev/null || true
    pkill -f "backend/system/resource_monitor" 2>/dev/null || true
    pkill -f "api_server.py" 2>/dev/null || true
}

cleanup_runtime() {
    print_step "Cleaning up runtime files..."
    
    # Remove FIFOs
    rm -f "$PRODUCER_FIFO" "$WORKER_FIFO" "$CONTROL_FIFO"
    
    # Remove lock files
    rm -f "${LOCKS_DIR}"/*.lock
    
    # Remove PID files
    rm -f "${PIDS_DIR}"/*.pid
    
    print_success "Runtime cleaned"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    echo
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  Real-Time Social Media Feed - Stop                          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo
    
    stop_all_processes
    cleanup_runtime
    
    print_success "System stopped completely"
    echo
}

main "$@"
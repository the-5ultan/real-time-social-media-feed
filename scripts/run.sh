#!/usr/bin/env bash
# Run script for Real-Time Social Media Feed
# Starts the complete system: backend processes and frontend with API server

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
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

print_step() { echo -e "${BLUE}[RUN]${NC} $*"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
print_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# =============================================================================
# GLOBALS
# =============================================================================

MANAGER_PID=""
PRODUCER_PIDS=()
WORKER_PIDS=()
SIMULATOR_PID=""
RESOURCE_MONITOR_PID=""
API_SERVER_PID=""

# =============================================================================
# CLEANUP
# =============================================================================

cleanup() {
    print_step "Shutting down system..."
    
    # Stop simulator
    if [[ -n "$SIMULATOR_PID" ]] && kill -0 "$SIMULATOR_PID" 2>/dev/null; then
        kill -TERM "$SIMULATOR_PID" 2>/dev/null
        wait "$SIMULATOR_PID" 2>/dev/null || true
    fi
    
    # Stop producers
    for pid in "${PRODUCER_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null
        fi
    done
    
    # Stop workers
    for pid in "${WORKER_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null
        fi
    done
    
    # Wait for processes
    for pid in "${PRODUCER_PIDS[@]}" "${WORKER_PIDS[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    
    # Stop manager
    if [[ -n "$MANAGER_PID" ]] && kill -0 "$MANAGER_PID" 2>/dev/null; then
        kill -TERM "$MANAGER_PID" 2>/dev/null
        wait "$MANAGER_PID" 2>/dev/null || true
    fi
    
    # Stop resource monitor
    if [[ -n "$RESOURCE_MONITOR_PID" ]] && kill -0 "$RESOURCE_MONITOR_PID" 2>/dev/null; then
        kill -TERM "$RESOURCE_MONITOR_PID" 2>/dev/null
        wait "$RESOURCE_MONITOR_PID" 2>/dev/null || true
    fi
    
    # Stop API server
    if [[ -n "$API_SERVER_PID" ]] && kill -0 "$API_SERVER_PID" 2>/dev/null; then
        kill -TERM "$API_SERVER_PID" 2>/dev/null
        wait "$API_SERVER_PID" 2>/dev/null || true
    fi
    
    # Cleanup runtime
    "${PROJECT_ROOT}/backend/system/cleanup.sh" 2>/dev/null || true
    
    print_success "System stopped"
}

# Setup signal handlers
trap cleanup EXIT INT TERM

# =============================================================================
# START FUNCTIONS
# =============================================================================

start_backend() {
    print_step "Starting backend..."
    
    # Initialize directories
    init_directories
    
    # Create FIFOs
    rm -f "$PRODUCER_FIFO" "$WORKER_FIFO" "$CONTROL_FIFO"
    mkfifo "$PRODUCER_FIFO" 2>/dev/null || true
    mkfifo "$WORKER_FIFO" 2>/dev/null || true
    mkfifo "$CONTROL_FIFO" 2>/dev/null || true
    
    # Start process manager (it will start producers and workers)
    print_step "Starting process manager..."
    "${PROJECT_ROOT}/backend/processes/manager.sh" start &
    MANAGER_PID=$!
    save_pid "manager" "$MANAGER_PID"
    log_process "manager" "START" "$MANAGER_PID" "Process manager started"
    
    sleep 2
    
    # Get actual producer/worker PIDs from manager
    for pid_file in "${PIDS_DIR}"/producer-*.pid; do
        [[ -f "$pid_file" ]] || continue
        local pid=$(cat "$pid_file")
        PRODUCER_PIDS+=("$pid")
    done
    
    for pid_file in "${PIDS_DIR}"/worker-*.pid; do
        [[ -f "$pid_file" ]] || continue
        local pid=$(cat "$pid_file")
        WORKER_PIDS+=("$pid")
    done
    
    print_success "Backend started (Manager: $MANAGER_PID, Producers: ${#PRODUCER_PIDS[@]}, Workers: ${#WORKER_PIDS[@]})"
}

start_simulator() {
    if [[ "${SIMULATION_ENABLED}" == "true" ]]; then
        print_step "Starting event simulator..."
        "${PROJECT_ROOT}/backend/processes/simulator.sh" &
        SIMULATOR_PID=$!
        save_pid "simulator" "$SIMULATOR_PID"
        log_process "simulator" "START" "$SIMULATOR_PID" "Event simulator started"
        print_success "Event simulator started (PID: $SIMULATOR_PID)"
    fi
}

start_resource_monitor() {
    print_step "Starting resource monitor..."
    "${PROJECT_ROOT}/backend/system/resource_monitor.sh" &
    RESOURCE_MONITOR_PID=$!
    save_pid "resource_monitor" "$RESOURCE_MONITOR_PID"
    log_process "resource_monitor" "START" "$RESOURCE_MONITOR_PID" "Resource monitor started"
    print_success "Resource monitor started (PID: $RESOURCE_MONITOR_PID)"
}

start_api_server() {
    print_step "Starting API server (frontend + backend API)..."
    
    if command -v python3 >/dev/null 2>&1; then
        # Start Python API server which serves frontend and API
        cd "$PROJECT_ROOT"
        python3 "${SCRIPT_DIR}/api_server.py" 8080 >"${LOGS_DIR}/api_server.log" 2>&1 &
        API_SERVER_PID=$!
        save_pid "api_server" "$API_SERVER_PID"
        log_process "api_server" "START" "$API_SERVER_PID" "API server started"
        
        # Wait for server to start
        sleep 2
        
        print_success "API server started at http://localhost:8080 (PID: $API_SERVER_PID)"
        print_step "Open http://localhost:8080 in your browser"
    else
        print_error "Python3 is required for the API server. Please install Python 3."
        exit 1
    fi
}

show_status() {
    echo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  SYSTEM RUNNING${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo
    echo "Process Manager:   PID $MANAGER_PID"
    echo "Producers:         ${#PRODUCER_PIDS[@]} processes (PIDs: ${PRODUCER_PIDS[*]})"
    echo "Workers:           ${#WORKER_PIDS[@]} processes (PIDs: ${WORKER_PIDS[*]})"
    [[ -n "$SIMULATOR_PID" ]] && echo "Simulator:         PID $SIMULATOR_PID"
    [[ -n "$RESOURCE_MONITOR_PID" ]] && echo "Resource Monitor:  PID $RESOURCE_MONITOR_PID"
    [[ -n "$API_SERVER_PID" ]] && echo "API Server:        PID $API_SERVER_PID (http://localhost:8080)"
    echo
    echo "Data Directory:    $DATA_DIR"
    echo "Logs Directory:    $LOGS_DIR"
    echo "Runtime Directory: $RUNTIME_DIR"
    echo
    echo -e "${YELLOW}Press Ctrl+C to stop the system${NC}"
    echo
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    print_banner
    
    # Check if already running
    if [[ -f "${PIDS_DIR}/manager.pid" ]] && kill -0 "$(cat "${PIDS_DIR}/manager.pid")" 2>/dev/null; then
        print_warn "System appears to be already running. Use ./scripts/stop.sh first."
        exit 1
    fi
    
    # Run setup if needed
    if [[ ! -f "$USERS_FILE" ]]; then
        print_warn "System not initialized. Running setup..."
        "${SCRIPT_DIR}/setup.sh"
    fi
    
    start_backend
    start_simulator
    start_resource_monitor
    start_api_server
    
    show_status
    
    # Wait for shutdown signal
    wait
}

main "$@"
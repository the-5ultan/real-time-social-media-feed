#!/usr/bin/env bash
# Run script for Real-Time Social Media Feed
# Starts the complete system: backend processes and frontend

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
FRONTEND_PID=""

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
    
    # Start process manager
    print_step "Starting process manager..."
    "${PROJECT_ROOT}/backend/processes/manager.sh" start &
    MANAGER_PID=$!
    save_pid "manager" "$MANAGER_PID"
    log_process "manager" "START" "$MANAGER_PID" "Process manager started"
    
    sleep 1
    
    # Start producers
    print_step "Starting ${DEFAULT_PRODUCERS} producer(s)..."
    for i in $(seq 1 "$DEFAULT_PRODUCERS"); do
        "${PROJECT_ROOT}/backend/processes/producer.sh" "producer-$i" &
        local pid=$!
        PRODUCER_PIDS+=("$pid")
        save_pid "producer-$i" "$pid"
        log_process "producer-$i" "START" "$pid" "Producer started"
    done
    
    # Start workers
    print_step "Starting ${DEFAULT_WORKERS} worker(s)..."
    for i in $(seq 1 "$DEFAULT_WORKERS"); do
        "${PROJECT_ROOT}/backend/processes/worker.sh" "worker-$i" &
        local pid=$!
        WORKER_PIDS+=("$pid")
        save_pid "worker-$i" "$pid"
        log_process "worker-$i" "START" "$pid" "Worker started"
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

start_frontend() {
    print_step "Starting frontend..."
    
    # Check if we have a simple HTTP server
    if command -v python3 >/dev/null 2>&1; then
        cd "$PROJECT_ROOT/frontend"
        python3 -m http.server 8080 >/dev/null 2>&1 &
        FRONTEND_PID=$!
        save_pid "frontend" "$FRONTEND_PID"
        print_success "Frontend server started at http://localhost:8080 (PID: $FRONTEND_PID)"
        print_step "Open http://localhost:8080 in your browser"
    elif command -v npx >/dev/null 2>&1; then
        cd "$PROJECT_ROOT/frontend"
        npx serve -p 8080 >/dev/null 2>&1 &
        FRONTEND_PID=$!
        save_pid "frontend" "$FRONTEND_PID"
        print_success "Frontend server started at http://localhost:8080 (PID: $FRONTEND_PID)"
    else
        print_warn "No HTTP server found. Open frontend/index.html directly in browser."
        print_warn "Install python3 or node.js for auto-server."
    fi
}

show_status() {
    echo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  SYSTEM RUNNING${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo
    echo "Process Manager:  PID $MANAGER_PID"
    echo "Producers:        ${#PRODUCER_PIDS[@]} processes (PIDs: ${PRODUCER_PIDS[*]})"
    echo "Workers:          ${#WORKER_PIDS[@]} processes (PIDs: ${WORKER_PIDS[*]})"
    [[ -n "$SIMULATOR_PID" ]] && echo "Simulator:        PID $SIMULATOR_PID"
    [[ -n "$RESOURCE_MONITOR_PID" ]] && echo "Resource Monitor: PID $RESOURCE_MONITOR_PID"
    [[ -n "$FRONTEND_PID" ]] && echo "Frontend Server:  PID $FRONTEND_PID (http://localhost:8080)"
    echo
    echo "Data Directory:   $DATA_DIR"
    echo "Logs Directory:   $LOGS_DIR"
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
    start_frontend
    
    show_status
    
    # Wait for shutdown signal
    wait
}

main "$@"
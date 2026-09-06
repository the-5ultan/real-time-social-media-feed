#!/usr/bin/env bash
# Setup script for Real-Time Social Media Feed
# Initializes the project structure and default data

set -Eeuo pipefail

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "${PROJECT_ROOT}/backend/config.sh"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

print_step() { echo -e "${BLUE}[SETUP]${NC} $*"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
print_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# =============================================================================
# SETUP FUNCTIONS
# =============================================================================

make_executable() {
    print_step "Making scripts executable..."
    
    find "$PROJECT_ROOT/backend" -name "*.sh" -exec chmod +x {} \;
    find "$PROJECT_ROOT/scripts" -name "*.sh" -exec chmod +x {} \;
    
    print_success "Scripts are now executable"
}

init_directories() {
    print_step "Initializing directories..."
    
    # Data directories
    mkdir -p "$USERS_DIR" "$POSTS_DIR" "$EVENTS_DIR" "$FEED_DIR" "$QUEUE_DIR" "$STATS_DIR"
    
    # Log directory
    mkdir -p "$LOGS_DIR"
    
    # Runtime directories
    mkdir -p "$PIDS_DIR" "$LOCKS_DIR" "$PIPES_DIR"
    
    print_success "Directories created"
}

create_default_users() {
    print_step "Creating default users..."
    
    local user_count=0
    for username in "${DEFAULT_USERS[@]}"; do
        local user_id=$(generate_user_id)
        local timestamp=$(get_timestamp)
        
        local user_json=$(json_object \
            "user_id" "$user_id" \
            "username" "$username" \
            "created_at" "$timestamp" \
            "followers_count" "0" \
            "following_count" "0" \
            "posts_count" "0")
        
        atomic_write "${USERS_DIR}/${user_id}.json" "$user_json"
        ((user_count++))
    done
    
    # Create users index
    local users_index="["
    local first=true
    for user_file in "$USERS_DIR"/*.json; do
        [[ -f "$user_file" ]] || continue
        [[ "$first" == true ]] || users_index+=","
        users_index+=$(cat "$user_file")
        first=false
    done
    users_index+="]"
    atomic_write "$USERS_FILE" "$users_index"
    
    print_success "Created $user_count default users"
}

create_empty_data_files() {
    print_step "Creating empty data files..."
    
    # Empty queue
    atomic_write "$QUEUE_FILE" "[]"
    atomic_write "$PRIORITY_QUEUE_FILE" "[]"
    
    # Empty feed
    atomic_write "$FEED_FILE" "[]"
    
    # Empty statistics
    local stats_json=$(json_object \
        "total_events" "0" \
        "processed_events" "0" \
        "pending_events" "0" \
        "total_posts" "0" \
        "total_likes" "0" \
        "total_comments" "0" \
        "total_shares" "0" \
        "total_follows" "0" \
        "active_producers" "0" \
        "active_workers" "0" \
        "processing_rate" "0" \
        "uptime_seconds" "0" \
        "last_updated" "$(get_timestamp)")
    atomic_write "$STATS_FILE" "$stats_json"
    
    # Empty log files
    > "$EVENTS_LOG"
    > "$WORKERS_LOG"
    > "$SYSTEM_LOG"
    
    print_success "Empty data files created"
}

create_fifos() {
    print_step "Creating FIFO pipes..."
    
    # Remove existing FIFOs
    rm -f "$PRODUCER_FIFO" "$WORKER_FIFO" "$CONTROL_FIFO"
    
    # Create new FIFOs
    mkfifo "$PRODUCER_FIFO" 2>/dev/null || true
    mkfifo "$WORKER_FIFO" 2>/dev/null || true
    mkfifo "$CONTROL_FIFO" 2>/dev/null || true
    
    print_success "FIFO pipes created"
}

verify_dependencies() {
    print_step "Verifying dependencies..."
    
    local missing=()
    
    for cmd in bash jq flock mkfifo date ps kill sleep; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing dependencies: ${missing[*]}"
        return 1
    fi
    
    # Check jq version
    local jq_version=$(jq --version 2>/dev/null || echo "unknown")
    print_success "All dependencies found (jq: $jq_version)"
}

run_tests() {
    print_step "Running basic validation tests..."
    
    # Test config loading
    source "${PROJECT_ROOT}/backend/config.sh"
    init_directories
    
    # Test common functions
    source "${PROJECT_ROOT}/backend/utils/common.sh"
    local test_id=$(generate_id "test_")
    [[ -n "$test_id" ]] || { print_error "generate_id failed"; return 1; }
    
    # Test JSON functions
    local test_json=$(json_object "key" "value" "num" "42")
    [[ "$test_json" == '{"key":"value","num":"42"}' ]] || { print_error "json_object failed"; return 1; }
    
    # Test validation
    source "${PROJECT_ROOT}/backend/utils/validation.sh"
    validate_data_structure || { print_error "Data structure validation failed"; return 1; }
    
    print_success "Basic tests passed"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    echo
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  Real-Time Social Media Feed - Setup                         ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo
    
    verify_dependencies || exit 1
    init_directories
    make_executable
    create_default_users
    create_empty_data_files
    create_fifos
    run_tests
    
    echo
    print_success "Setup completed successfully!"
    echo
    echo "Next steps:"
    echo "  1. Start the system:  ./scripts/run.sh"
    echo "  2. Open frontend:     Open frontend/index.html in browser"
    echo "  3. Run tests:         ./scripts/test.sh"
    echo
}

main "$@"
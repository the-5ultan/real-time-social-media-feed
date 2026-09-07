# Operating Systems Concepts Demonstrated

This document maps each OS concept to its concrete implementation in the Real-Time Social Media Feed project.

## 1. Process Management

### Concept
Operating systems manage processes as units of execution with their own memory space, resources, and scheduling.

### Implementation

**Real Processes with Actual PIDs**
```bash
# producer.sh - runs as independent process
"${PROJECT_ROOT}/backend/processes/producer.sh" "producer-1" &
PRODUCER_PID=$!  # Actual OS PID
save_pid "producer-1" "$PRODUCER_PID"
```

**Process Creation and Tracking**
- `manager.sh`: Starts/stops producers and workers as background processes
- PID files in `runtime/pids/` track each process
- `ps`, `kill`, `wait` used for process control

**Process States**
```bash
# In manager.sh - monitoring process health
if ! kill -0 "$pid" 2>/dev/null; then
    # Process died - restart it
    start_producer "$name"
fi
```

**Process Lifecycle**
```
START → INITIALIZE → CREATE IPC → START WORKERS → START PRODUCERS
    ↓                                                    ↓
    ←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←
                                    RUN
                                    ↓
                          STOP PRODUCERS → PROCESS PENDING
                                    ↓
                          STOP WORKERS → SAVE STATE → CLEANUP → EXIT
```

## 2. Multiprocessing

### Concept
Multiple processes executing concurrently, utilizing multiple CPU cores.

### Implementation

**Concurrent Producers and Workers**
```bash
# run.sh starts multiple processes
for i in $(seq 1 "$DEFAULT_PRODUCERS"); do
    "${PROJECT_ROOT}/backend/processes/producer.sh" "producer-$i" &
    PRODUCER_PIDS+=($!)
done

for i in $(seq 1 "$DEFAULT_WORKERS"); do
    "${PROJECT_ROOT}/backend/processes/worker.sh" "worker-$i" &
    WORKER_PIDS+=($!)
done
```

**Actual Parallelism**
- Each producer runs in its own process with independent timer
- Each worker independently polls and processes queue
- Resource monitor runs independently
- Simulator runs independently
- API server runs in separate Python process

**Process Monitoring**
```bash
# Real-time process status for frontend
get_process_status() {
    for pid_file in "${PIDS_DIR}"/producer-*.pid; do
        local pid=$(cat "$pid_file")
        local status="STOPPED"
        kill -0 "$pid" 2>/dev/null && status="RUNNING"
        # Return PID, status, start_time, events_processed
    done
}
```

## 3. Inter-Process Communication (IPC)

### Concept
Mechanisms for processes to exchange data and synchronize.

### Implementation

**Named Pipes (FIFOs)**
```bash
# Creating FIFOs
mkfifo "$PRODUCER_FIFO"  # /tmp/feed/pipes/producer.fifo
mkfifo "$WORKER_FIFO"    # /tmp/feed/pipes/worker.fifo
mkfifo "$CONTROL_FIFO"   # /tmp/feed/pipes/control.fifo
```

**Communication Patterns**

1. **Producer → Worker (Event Passing)**
```bash
# Producer sends event
fifo_producer_send_event() {
    local event_json="$1"
    local message=$(json_object "type" "EVENT" "payload" "$event_json")
    fifo_write "$PRODUCER_FIFO" "$message"
}

# Worker receives event
fifo_worker_receive_event() {
    local line=$(fifo_read_timeout "$PRODUCER_FIFO" 1)
    # Parse and return event payload
}
```

2. **Control Commands (Manager → All)**
```bash
# Broadcast to all workers
fifo_broadcast() {
    local message="$1"
    local msg_json=$(json_object "type" "BROADCAST" "payload" "$message")
    fifo_write "$CONTROL_FIFO" "$msg_json"
}
```

3. **Non-blocking I/O with Timeout**
```bash
fifo_read_timeout() {
    local fifo_path="$1"
    local timeout="${2:-1}"
    if read -t "$timeout" line < "$fifo_path"; then
        echo "$line"
        return 0
    fi
    return 1
}
```

## 4. Producer-Consumer Problem

### Classic Problem
Producers generate data, consumers process it, shared buffer has finite capacity.

### Implementation

**Bounded Buffer (Queue)**
```bash
# Queue with maximum size
readonly QUEUE_MAX_SIZE=10000

queue_enqueue() {
    if queue_is_full "$queue_file"; then
        log_queue "ENQUEUE_FAILED" ... "Queue full, dropping event"
        return 1
    fi
    # Add to rear of queue
}
```

**Multiple Producers, Multiple Consumers**
- 3+ producers generating events concurrently
- 2+ workers consuming events concurrently
- Queue protects against overflow/underflow

**Synchronization via Mutex**
```bash
queue_enqueue() {
    (
        flock -x 200
        # Critical section: check full, add event, write file
    ) 200>"$QUEUE_LOCK"
}
```

**Blocking vs Non-blocking**
- Producers: Non-blocking enqueue (drop if full, log warning)
- Workers: Blocking dequeue with poll interval (sleep when empty)

## 5. Synchronization

### Concept
Coordinating access to shared resources to prevent race conditions.

### Implementation

**Mutual Exclusion with flock**
```bash
# Low-level lock functions
lock_acquire() {
    local lock_name="$1"
    local timeout="${2:-10}"
    local lock_file="${LOCKS_DIR}/${lock_name}.lock"
    touch "$lock_file"
    
    local count=0
    while ! flock -x -n 200 2>/dev/null; do
        [[ $count -ge $timeout ]] && return 1
        sleep 1
        ((count++))
    done
}

with_lock() {
    local lock_name="$1"
    shift
    local lock_file="${LOCKS_DIR}/${lock_name}.lock"
    touch "$lock_file"
    (
        flock -x 200
        "$@"
    ) 200>"$lock_file"
}
```

**Predefined Locks for Resources**
```bash
# Feed lock
feed_lock() { with_lock "feed" "$@"; }

# Queue lock
queue_lock() { with_lock "queue" "$@"; }

# Statistics lock
stats_lock() { with_lock "stats" "$@"; }

# Users lock
users_lock() { with_lock "users" "$@"; }
```

**Usage in Data Structures**
```bash
# Feed operations protected
feed_add_post() {
    (
        flock -x 200
        local content=$(read_file "$feed_file")
        local new_feed=$(echo "$content" | jq --argjson post "$post_json" '[$post] + .')
        atomic_write "$feed_file" "$new_feed"
    ) 200>"$FEED_LOCK"
}
```

**Lock Inspection and Debugging**
```bash
lock_info() {
    local lock_name="$1"
    local lock_file="${LOCKS_DIR}/${lock_name}.lock"
    # Returns JSON with name, file, held status
}

lock_list() {
    # Lists all locks with status
}
```

## 6. Mutual Exclusion

### Concept
Ensuring only one process accesses a critical section at a time.

### Implementation

**Critical Sections Protected**
| Critical Section | Lock | Operations |
|-----------------|------|------------|
| Feed modification | feed.lock | Add/remove/update posts, add comments |
| Queue modification | queue.lock | Enqueue/dequeue/clear/remove |
| Statistics update | stats.lock | Increment/decrement/set counters |
| User management | users.lock | Create/update users, increment stats |

**Atomic File Operations**
```bash
atomic_write() {
    local file="$1"
    local content="$2"
    local temp_file="${file}.tmp.$$"
    echo "$content" > "$temp_file"
    mv "$temp_file" "$file"  # Atomic on POSIX
}
```

**Lock-Free Reads**
- Read operations don't require locks (JSON parsing is fast)
- Only write operations acquire exclusive locks
- Acceptable for this use case (eventual consistency for reads)

## 7. Dynamic Data Structures

### Concept
Data structures that grow/shrink at runtime with efficient operations.

### Implementation

**Feed (Linked-List Style with JSON Array)**
```bash
# Operations: O(n) for search, O(1) for insert at front
feed_add_post()      # Insert at front (newest first)
feed_remove_post()   # Filter by ID
feed_update_post()   # Map and update
feed_find_post()     # Search by ID
feed_search_posts()  # Search by content (case-insensitive)
feed_search_by_user() # Search by user ID
feed_get_all()       # Traverse all
feed_get_page()      # Pagination
```

**Queue (FIFO with JSON Array)**
```bash
# Operations: O(n) for dequeue (shift), O(1) for enqueue
queue_enqueue()      # Push to rear
queue_dequeue()      # Shift from front
queue_peek()         # View front without removing
queue_size()         # Length
queue_is_empty()     # Check empty
```

**Priority Queue (Bucket-Based)**
```bash
# Multiple FIFO queues, one per priority level
# Stored as: {"1": [...], "2": [...], "3": [...]}
pqueue_enqueue()     # Add to priority bucket
pqueue_dequeue()     # Find lowest priority with events, pop front
pqueue_peek()        # View highest priority event
```

**Complexity Analysis**
| Operation | Feed | Queue | Priority Queue |
|-----------|------|-------|----------------|
| Insert | O(1)* | O(1) | O(1) |
| Delete | O(n) | O(n) | O(p) |
| Search | O(n) | O(n) | O(n) |
| Peek | O(1) | O(1) | O(p) |
| Size | O(1) | O(1) | O(p) |

*Insert at front; p = number of priority levels

## 8. File System Operations

### Concept
Persistent storage, atomic operations, directory management.

### Implementation

**Directory Structure Initialization**
```bash
init_directories() {
    local dirs=(
        "${USERS_DIR}" "${POSTS_DIR}" "${EVENTS_DIR}"
        "${FEED_DIR}" "${QUEUE_DIR}" "${STATS_DIR}"
        "${LOGS_DIR}" "${PIDS_DIR}" "${LOCKS_DIR}" "${PIPES_DIR}"
    )
    for dir in "${dirs[@]}"; do mkdir -p "$dir"; done
}
```

**Atomic Writes (Crash-Safe)**
```bash
atomic_write() {
    local file="$1"
    local content="$2"
    local temp_file="${file}.tmp.$$"
    echo "$content" > "$temp_file"
    mv "$temp_file" "$file"  # Atomic rename
}
```

**State Persistence and Recovery**
```bash
save_state() {
    stats_get_all > "${STATS_DIR}/state_stats.json"
    queue_get_all > "${QUEUE_DIR}/state_queue.json"
    pqueue_get_all > "${QUEUE_DIR}/state_priority_queue.json"
    feed_get_all > "${FEED_DIR}/state_feed.json"
    list_pids > "${PIDS_DIR}/state_pids.txt"
}

restore_state() {
    [[ -f "${QUEUE_DIR}/state_queue.json" ]] && \
        cp "${QUEUE_DIR}/state_queue.json" "$QUEUE_FILE"
    # Feed already persistent
}
```

## 9. Process Lifecycle Management

### Concept
Managing processes from creation to termination with proper cleanup.

### Implementation

**Initialization Phase**
```bash
manager_init() {
    log_process "manager" "START" "$$" "Process manager initialized"
    stats_init
    trap 'manager_shutdown' EXIT INT TERM
}
```

**Runtime Monitoring**
```bash
monitor_processes() {
    # Check producers
    for pid_file in "${PIDS_DIR}"/producer-*.pid; do
        if ! kill -0 "$pid" 2>/dev/null; then
            log_warn "Producer died, restarting..."
            remove_pid "$name"
            start_producer "$name"
        fi
    done
}
```

**Graceful Shutdown**
```bash
manager_shutdown() {
    log_process "manager" "STOP" "$$" "Process manager shutting down"
    stop_all_producers
    stop_all_workers
}

stop_producer() {
    local pid=$(load_pid "$producer_name")
    if kill -0 "$pid" 2>/dev/null; then
        kill_graceful "$pid" 5  # TERM, wait 5s, then KILL
    fi
    remove_pid "$producer_name"
}
```

**Signal Handling**
```bash
setup_signal_handlers() {
    trap "${cleanup_func}" EXIT
    trap "${cleanup_func}; exit 130" INT
    trap "${cleanup_func}; exit 143" TERM
}
```

## 10. Resource Monitoring

### Concept
Observing system resource utilization (CPU, memory, disk, processes).

### Implementation

**CPU Usage (from /proc/stat)**
```bash
get_cpu_usage() {
    local stat1=$(grep '^cpu ' /proc/stat)
    sleep 0.1
    local stat2=$(grep '^cpu ' /proc/stat)
    
    local idle1=$(echo "$stat1" | awk '{print $5}')
    local idle2=$(echo "$stat2" | awk '{print $5}')
    local total1=$(echo "$stat1" | awk '{sum=0; for(i=2;i<=NF;i++) sum+=$i; print sum}')
    local total2=$(echo "$stat2" | awk '{sum=0; for(i=2;i<=NF;i++) sum+=$i; print sum}')
    
    local idle_diff=$((idle2 - idle1))
    local total_diff=$((total2 - total1))
    echo $((100 * (total_diff - idle_diff) / total_diff))
}
```

**Memory Usage (from /proc/meminfo)**
```bash
get_memory_usage() {
    local total=$(grep 'MemTotal:' /proc/meminfo | awk '{print $2}')
    local available=$(grep 'MemAvailable:' /proc/meminfo | awk '{print $2}')
    local used=$((total - available))
    local usage=$((100 * used / total))
    # Returns JSON with total, available, used, usage_percent
}
```

**System Uptime**
```bash
get_system_uptime() {
    local uptime_sec=$(cat /proc/uptime | awk '{print int($1)}')
    local days=$((uptime_sec / 86400))
    local hours=$(( (uptime_sec % 86400) / 3600 ))
    local minutes=$(( (uptime_sec % 3600) / 60 ))
    # Returns seconds and formatted string
}
```

**Process Count**
```bash
get_process_count() {
    local total=$(ps aux | wc -l)
    local our_processes=0
    for pid_file in "${PIDS_DIR}"/*.pid; do
        kill -0 "$(cat "$pid_file")" 2>/dev/null && ((our_processes++))
    done
}
```

## 11. Logging and Observability

### Concept
Structured logging for debugging, monitoring, and audit trails.

### Implementation

**Structured Log Format**
```
[2026-09-07 10:30:00] PID=12345 USER=testuser CATEGORY=EVENT LEVEL=INFO EVENT_ID=evt_abc EVENT_TYPE=POST STATUS=CREATED MSG="Event created"
```

**Log Categories**
- EVENT: Event lifecycle (created, queued, processed, failed)
- WORKER: Worker activity (processing, completed)
- SYSTEM: System events (start, stop, errors)
- PRODUCER: Producer activity
- QUEUE: Queue operations (enqueue, dequeue, size)
- FEED: Feed operations (add, remove, update)
- SYNC: Lock acquire/release/timeout
- PROCESS: Process lifecycle (start, stop, restart, crash)

**Log Rotation**
```bash
rotate_logs() {
    local max_lines="${1:-10000}"
    for log_file in "$EVENTS_LOG" "$WORKERS_LOG" "$SYSTEM_LOG"; do
        if [[ $(wc -l < "$log_file") -gt $max_lines ]]; then
            tail -n "$max_lines" "$log_file" > "${log_file}.tmp"
            mv "${log_file}.tmp" "$log_file"
        fi
    done
}
```

## Summary Matrix

| OS Concept | Implementation Files | Key Functions |
|------------|---------------------|---------------|
| Process Management | `processes/manager.sh`, `system/process_manager.sh` | `start_producer`, `stop_worker`, `monitor_processes` |
| Multiprocessing | `scripts/run.sh`, `processes/*.sh` | Background `&`, `$!`, `wait`, `kill` |
| IPC (FIFOs) | `ipc/fifo.sh` | `mkfifo`, `fifo_write`, `fifo_read_timeout` |
| Producer-Consumer | `processes/producer.sh`, `processes/worker.sh`, `datastructures/queue.sh` | `queue_enqueue`, `queue_dequeue`, poll loop |
| Synchronization | `synchronization/locks.sh` | `flock`, `with_lock`, `lock_acquire` |
| Mutual Exclusion | `synchronization/locks.sh`, all data structures | `feed_lock`, `queue_lock`, `stats_lock` |
| Dynamic Data Structures | `datastructures/feed.sh`, `queue.sh`, `priority_queue.sh` | Insert, delete, search, update, traverse |
| File System | `utils/common.sh`, `system/cleanup.sh` | `atomic_write`, `save_state`, `restore_state` |
| Process Lifecycle | `processes/manager.sh`, `system/cleanup.sh` | `trap`, `kill_graceful`, `cleanup_all` |
| Resource Monitoring | `system/resource_monitor.sh` | `/proc` parsing, periodic logging |
# IPC Documentation

This document describes the Inter-Process Communication (IPC) implementation using Named Pipes (FIFOs) in the Real-Time Social Media Feed project.

## Overview

The system uses three named pipes (FIFOs) for communication between processes:

| FIFO | Path | Purpose | Direction |
|------|------|---------|-----------|
| Producer FIFO | `runtime/pipes/producer.fifo` | Events from producers to workers | Producer → Worker |
| Worker FIFO | `runtime/pipes/worker.fifo` | Results from workers to producers | Worker → Producer |
| Control FIFO | `runtime/pipes/control.fifo` | System commands and broadcasts | Manager → All |

## FIFO Creation

```bash
# In ipc/fifo.sh
fifo_create_all() {
    mkdir -p "$PIPES_DIR"
    rm -f "$PRODUCER_FIFO" "$WORKER_FIFO" "$CONTROL_FIFO"
    mkfifo "$PRODUCER_FIFO" 2>/dev/null || true
    mkfifo "$WORKER_FIFO" 2>/dev/null || true
    mkfifo "$CONTROL_FIFO" 2>/dev/null || true
}
```

## Message Format

All messages are JSON objects with a standard envelope:

```json
{
  "type": "EVENT|RESULT|BROADCAST|COMMAND",
  "payload": {},
  "timestamp": "2026-09-07 10:30:00",
  "pid": 12345
}
```

### Event Message (Producer → Worker)
```json
{
  "type": "EVENT",
  "payload": {
    "event_id": "evt_1234567890_1234",
    "user_id": "user_ali",
    "user_name": "Ali",
    "event_type": "POST",
    "content": "Hello world!",
    "target_post": "",
    "target_user": "",
    "priority": 5,
    "timestamp": "2026-09-07 10:30:00",
    "status": "QUEUED",
    "pid": 12345
  },
  "timestamp": "2026-09-07 10:30:00",
  "pid": 12345
}
```

### Result Message (Worker → Producer)
```json
{
  "type": "RESULT",
  "event_id": "evt_1234567890_1234",
  "status": "PROCESSED",
  "result": "Post added to feed",
  "timestamp": "2026-09-07 10:30:01",
  "worker_pid": 12346
}
```

### Broadcast Message (Manager → All)
```json
{
  "type": "BROADCAST",
  "payload": "SHUTDOWN",
  "timestamp": "2026-09-07 10:30:00"
}
```

### Command Message (API → Manager)
```json
{
  "command": "add_producer",
  "args": "",
  "timestamp": "2026-09-07 10:30:00",
  "pid": 12347
}
```

## Core Operations

### Writing to FIFO (Non-blocking with Timeout)
```bash
fifo_write() {
    local fifo_path="$1"
    local message="$2"
    local timeout="${3:-5}"
    
    # Check FIFO exists
    [[ -p "$fifo_path" ]] || return 1
    
    # Write in background to avoid blocking
    (
        echo "$message" > "$fifo_path"
    ) &
    local write_pid=$!
    
    # Wait for completion with timeout
    local count=0
    while kill -0 "$write_pid" 2>/dev/null && [[ $count -lt $timeout ]]; do
        sleep 1
        ((count++))
    done
    
    # Force kill if timeout
    if kill -0 "$write_pid" 2>/dev/null; then
        kill -KILL "$write_pid" 2>/dev/null
        return 1
    fi
    
    wait "$write_pid" 2>/dev/null
    return 0
}
```

### Reading from FIFO (Blocking)
```bash
fifo_read() {
    local fifo_path="$1"
    [[ -p "$fifo_path" ]] || return 1
    cat "$fifo_path"  # Blocks until data available
}
```

### Reading with Timeout
```bash
fifo_read_timeout() {
    local fifo_path="$1"
    local timeout="${2:-1}"
    [[ -p "$fifo_path" ]] || return 1
    
    local line
    if read -t "$timeout" line < "$fifo_path"; then
        echo "$line"
        return 0
    fi
    return 1
}
```

## High-Level IPC Interface

### Producer Side
```bash
# Initialize IPC for producer
ipc_producer_init() {
    fifo_create_all
}

# Send event to worker pool
fifo_producer_send_event() {
    local event_json="$1"
    local message=$(json_object "type" "EVENT" "payload" "$event_json")
    fifo_write "$PRODUCER_FIFO" "$message"
}

# Receive result from worker
fifo_producer_receive_result() {
    local timeout="${1:-1}"
    local line
    if line=$(fifo_read_timeout "$WORKER_FIFO" "$timeout"); then
        local type=$(json_get "$line" "type")
        [[ "$type" == "RESULT" ]] && echo "$line"
    fi
}
```

### Worker Side
```bash
# Initialize IPC for worker
ipc_worker_init() {
    # FIFOs already created by manager
}

# Receive event from producer
fifo_worker_receive_event() {
    local timeout="${1:-1}"
    local line
    if line=$(fifo_read_timeout "$PRODUCER_FIFO" "$timeout"); then
        local type=$(json_get "$line" "type")
        [[ "$type" == "EVENT" ]] && json_get "$line" "payload"
    fi
}

# Send result back to producer
fifo_worker_send_result() {
    local event_id="$1"
    local status="$2"
    local result="${3:-}"
    local message=$(json_object \
        "type" "RESULT" \
        "event_id" "$event_id" \
        "status" "$status" \
        "result" "$result" \
        "timestamp" "$(get_timestamp)" \
        "worker_pid" "$$")
    fifo_write "$WORKER_FIFO" "$message"
}
```

### Manager/Control Side
```bash
# Initialize IPC for manager
ipc_manager_init() {
    fifo_create_all
}

# Send command to control FIFO
fifo_send_command() {
    local command="$1"
    local args="${2:-}"
    local message=$(json_object "command" "$command" "args" "$args")
    fifo_write "$CONTROL_FIFO" "$message"
}

# Listen for commands
fifo_listen_commands() {
    local handler_func="$1"
    while true; do
        local line
        if line=$(fifo_read_timeout "$CONTROL_FIFO" 1); then
            local cmd=$(json_get "$line" "command")
            local args=$(json_get "$line" "args")
            $handler_func "$cmd" "$args"
        fi
    done
}

# Broadcast to all workers
fifo_broadcast() {
    local message="$1"
    local msg_json=$(json_object "type" "BROADCAST" "payload" "$message")
    fifo_write "$CONTROL_FIFO" "$msg_json"
}
```

## Communication Patterns

### Pattern 1: Fire-and-Forget (Producer → Queue)
Producer enqueues directly to shared queue file, no FIFO needed for this path:
```
Producer Process
       │
       ▼
queue_enqueue() ──► Queue File (JSON)
       │
       ▼ (Worker polls file directly)
Worker Process
```

### Pattern 2: Request-Response (Producer ↔ Worker via FIFO)
Used when producer needs confirmation:
```
Producer                    Worker
   │                          │
   ├─EVENT (FIFO)──────────► │
   │                          │
   │                   Process event
   │                          │
   │ ◄──RESULT (FIFO)────────┤
   │                          │
```

### Pattern 3: Broadcast (Manager → All Workers)
```
Manager
   │
   ├─BROADCAST (FIFO)──► Worker 1
   ├─BROADCAST (FIFO)──► Worker 2
   └─BROADCAST (FIFO)──► Worker 3
```

## Integration with Queue System

The primary event flow uses the shared queue file rather than FIFOs for the main producer-consumer path:

```
┌─────────────┐     queue_enqueue()      ┌─────────────┐
│  Producer   │ ──────────────────────►  │  Event Queue │
│  Process    │     (file + flock)       │  (JSON file) │
└─────────────┘                          └──────┬──────┘
                                                 │
                                                 │ queue_dequeue()
                                                 ▼
                                        ┌─────────────────┐
                                        │   Worker        │
                                        │  Process        │
                                        └─────────────────┘
```

FIFOs are used for:
1. **Control commands** (start/stop/scale processes)
2. **Real-time notifications** (optional worker→producer results)
3. **Broadcast messages** (shutdown, config changes)

## Concurrency Considerations

### Multiple Producers Writing
- `fifo_write` uses background subprocess + timeout
- Multiple producers can write concurrently
- Kernel handles FIFO buffering (typically 64KB)

### Multiple Workers Reading
- Only ONE worker should read from PRODUCER_FIFO at a time
- Current design: workers poll queue file directly, not FIFO
- FIFO reserved for control/result messages

### FIFO Buffer Limits
- Linux pipe buffer: 64KB (configurable via `/proc/sys/fs/pipe-max-size`)
- Large events may block if buffer full
- Timeout mechanism prevents deadlock

## Error Handling

### Common Errors
| Error | Cause | Handling |
|-------|-------|----------|
| "FIFO does not exist" | FIFO not created or removed | Auto-create in `fifo_create_all` |
| "FIFO write timeout" | No reader, buffer full | Return error, log warning |
| "Broken pipe" | Reader closed | Return error, caller handles |

### Cleanup
```bash
fifo_remove_all() {
    rm -f "$PRODUCER_FIFO" "$WORKER_FIFO" "$CONTROL_FIFO"
}

# Called on:
# - System shutdown (cleanup.sh)
# - Pre-start cleanup (cleanup_prestart)
# - Emergency cleanup (cleanup_emergency)
```

## Security

- FIFOs created in project-specific directory (`runtime/pipes/`)
- No network exposure (local filesystem only)
- Messages validated via JSON parsing
- No executable code in messages

## Testing

```bash
# Test FIFO creation
fifo_create_all
[[ -p "$PRODUCER_FIFO" ]] && echo "PASS"

# Test write/read
echo "test" > "$PRODUCER_FIFO" &
read -t 1 line < "$PRODUCER_FIFO"
[[ "$line" == "test" ]] && echo "PASS"

# Test cleanup
fifo_remove_all
[[ ! -p "$PRODUCER_FIFO" ]] && echo "PASS"
```

## Limitations

1. **Unidirectional**: Each FIFO is one-way
2. **Local only**: No network transparency
3. **No persistence**: Messages lost if reader not ready
4. **Buffer limits**: Large payloads may block
5. **Single reader**: Multiple readers on same FIFO causes message distribution issues

## Future Improvements

1. **Unix Domain Sockets**: Bidirectional, better performance
2. **Message Acknowledgment**: Reliable delivery guarantee
3. **Priority FIFOs**: Separate pipes for high-priority events
4. **Batch Operations**: Reduce FIFO open/close overhead
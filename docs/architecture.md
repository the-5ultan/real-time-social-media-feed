# Architecture Documentation

## System Overview

The Real-Time Social Media Feed is a Bash-based implementation demonstrating core Operating Systems concepts through a working social media feed simulator. The system follows a producer-consumer architecture with multiple concurrent processes communicating via named pipes (FIFOs) and synchronized using flock-based mutual exclusion.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
                        FRONTEND (HTML/CSS/JS)
                              │
                              ▼
                    ┌─────────────────┐
                    │  API Server     │
                    │  (Python HTTP)  │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
      ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
      │  PRODUCERS  │ │  WORKERS    │ │  MANAGER    │
      │  (3-10)     │ │  (2-10)     │ │  (1)        │
      └──────┬──────┘ └──────┬──────┘ └──────┬──────┘
             │               │               │
             └───────────────┼───────────────┘
                             ▼
                    ┌─────────────────┐
                    │  EVENT QUEUE    │
                    │  (FIFO + PQ)    │
                    └────────┬────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │  DYNAMIC FEED   │
                    │  (JSON Array)   │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
       ┌────────────┐ ┌────────────┐ ┌────────────┐
       │   USERS    │ │   POSTS    │ │  STATISTICS│
       └────────────┘ └────────────┘ └────────────┘
```

## Component Details

### 1. Configuration Layer (`backend/config.sh`)
Centralized configuration with all system parameters:
- Directory paths (data, logs, runtime)
- Process counts and timing
- Queue and feed limits
- Event types and priorities
- IPC endpoints (FIFO paths)
- Logging configuration

### 2. Utility Layer (`backend/utils/`)
- **common.sh**: JSON utilities, ID generation, file operations, process management, signal handling
- **logger.sh**: Structured logging with timestamps, PIDs, categories, levels
- **validation.sh**: Input validation for events, users, posts, queues, feeds

### 3. Data Structures (`backend/datastructures/`)
- **feed.sh**: Dynamic feed with insert/delete/search/update/traverse operations
- **queue.sh**: FIFO event queue with enqueue/dequeue/peek/size operations
- **priority_queue.sh**: Priority-based queue (lower number = higher priority)

All data structures use JSON files for persistence and flock for thread safety.

### 4. Services Layer (`backend/services/`)
- **user_service.sh**: User CRUD operations, search, statistics
- **event_service.sh**: Event creation, validation, persistence, processing
- **feed_service.sh**: High-level feed operations (create post, like, comment, share, follow)
- **statistics_service.sh**: System statistics tracking and reporting

### 5. Process Layer (`backend/processes/`)
- **producer.sh**: Generates social media events at configurable intervals
- **worker.sh**: Consumes events from queue and processes them
- **manager.sh**: Process lifecycle management (start/stop/monitor/restart)
- **simulator.sh**: Generates burst events for demonstration

### 6. IPC Layer (`backend/ipc/fifo.sh`)
Named pipe implementation for inter-process communication:
- Producer FIFO: Events from producers to workers
- Worker FIFO: Results from workers to producers
- Control FIFO: System commands and broadcasts

### 7. Synchronization Layer (`backend/synchronization/locks.sh`)
Flock-based mutual exclusion:
- Feed lock, Queue lock, Stats lock, Users lock
- High-level helpers: `with_lock`, `lock_acquire`, `lock_try`
- Lock inspection and force-release for emergencies

### 8. System Layer (`backend/system/`)
- **process_manager.sh**: High-level process management with CLI
- **resource_monitor.sh**: System resource monitoring (/proc parsing)
- **cleanup.sh**: Graceful shutdown, state save/restore, emergency cleanup

### 9. Scripts (`scripts/`)
- **setup.sh**: Initialize directories, create default users, verify dependencies
- **run.sh**: Start complete system (backend + API server)
- **stop.sh**: Graceful shutdown of all processes
- **clean.sh**: Remove all generated data
- **test.sh**: Comprehensive test suite
- **api_server.py**: Python HTTP server bridging frontend to Bash backend

### 10. Frontend (`frontend/`)
- **index.html**: Single-page dashboard
- **css/style.css**: Dark theme, responsive grid layout
- **js/app.js**: Real-time data fetching, UI updates, command sending

## Data Flow

### Event Generation Flow
```
User Action / Producer Timer
        │
        ▼
create_event() → Event JSON
        │
        ▼
queue_event() → STATUS_QUEUED
        │
        ▼
queue_enqueue() / pqueue_enqueue()
        │
        ▼
Queue File (JSON) + FIFO notification
```

### Event Processing Flow
```
Worker polls queue
        │
        ▼
queue_dequeue() / pqueue_dequeue()
        │
        ▼
process_event() → STATUS_PROCESSING
        │
        ├── POST    → create post → feed_add_post() → stats_increment()
        ├── LIKE    → feed_increment_likes() → stats_increment()
        ├── COMMENT → feed_add_comment() → stats_increment()
        ├── SHARE   → feed_increment_shares() → stats_increment()
        ├── FOLLOW  → user stats update → stats_increment()
        └── NOTIFICATION → stats_increment()
        │
        ▼
update_event_status() → STATUS_PROCESSED
```

### Persistence Flow
```
Data Change
    │
    ▼
atomic_write() → temp file → mv (atomic)
    │
    ▼
File System (JSON)
    │
    ▼
On Restart: restore_state() → load from state files
```

## Concurrency Model

### Process Hierarchy
```
run.sh (PID 1)
    ├── manager.sh (daemon)
    │   ├── producer-1, producer-2, ... (background)
    │   └── worker-1, worker-2, ... (background)
    ├── simulator.sh (background)
    ├── resource_monitor.sh (background)
    └── api_server.py (background)
```

### Synchronization Points
| Resource | Lock File | Protected Operations |
|----------|-----------|---------------------|
| Feed | feed.lock | Add/remove/update posts, search |
| Queue | queue.lock | Enqueue/dequeue/peek/clear |
| Priority Queue | queue.lock | PQ enqueue/dequeue/peek |
| Statistics | stats.lock | Increment/decrement/set/get |
| Users | users.lock | Create/update/search users |

### Lock Implementation
```bash
# Using flock with file descriptor 200
(
    flock -x 200
    # Critical section
    atomic_write "$file" "$content"
) 200>"$LOCK_FILE"
```

## Communication Protocols

### FIFO Message Format (JSON)
```json
{
  "type": "EVENT|RESULT|BROADCAST|COMMAND",
  "payload": {},
  "timestamp": "2026-09-07 10:30:00",
  "pid": 12345
}
```

### API Endpoints
| Endpoint | Method | Description |
|----------|--------|-------------|
| /api/status | GET | System process status |
| /api/feed | GET | Feed posts with pagination |
| /api/processes | GET | Process list with PIDs |
| /api/queue | GET | Queue statistics and events |
| /api/stats | GET | System statistics |
| /api/resources | GET | System resources (CPU, memory, disk) |
| /api/logs | GET | Filtered log entries |
| /api/command | POST | Execute system command |
| /api/health | GET | System health check |

## Persistence Strategy

### Files Persisted
| Data | File | Format |
|------|------|--------|
| Users | data/users/users.json | JSON array index + individual files |
| Posts | data/posts/*.json | Individual JSON files |
| Feed | data/feed/feed.json | JSON array (newest first) |
| Events | data/events/*.json | Individual JSON files |
| Queue | data/queue/event_queue.json | JSON array (FIFO) |
| Priority Queue | data/queue/priority_queue.json | JSON object (priority buckets) |
| Statistics | data/stats/statistics.json | JSON object |
| Logs | logs/*.log | Structured text lines |

### Atomic Writes
All file writes use atomic_write():
```bash
atomic_write() {
    local file="$1"
    local content="$2"
    local temp_file="${file}.tmp.$$"
    echo "$content" > "$temp_file"
    mv "$temp_file" "$file"
}
```

## Security Considerations

- No network exposure (localhost only)
- Input validation on all user-provided data
- No eval or dynamic code execution
- Temporary files use $$ (PID) for uniqueness
- FIFOs created with restrictive permissions

## Scalability Limits

| Component | Limit | Reason |
|-----------|-------|--------|
| Feed posts | 1000 | Memory/performance |
| Queue size | 10000 | File I/O performance |
| Producers | 10 | Process management overhead |
| Workers | 10 | Process management overhead |
| Bash arrays | ~1000 elements | Performance degradation |

## Deployment Requirements

### Fedora/Linux
- bash 4.0+
- jq 1.6+
- flock (util-linux)
- python3 (for API server)
- mkfifo, ps, kill, date, sleep

### Windows
- WSL2 with Ubuntu/Fedora
- Or Git Bash (limited FIFO support)

## Monitoring and Observability

### Log Format
```
[2026-09-07 10:30:00] PID=12345 USER=testuser CATEGORY=EVENT LEVEL=INFO EVENT_ID=evt_abc EVENT_TYPE=POST STATUS=CREATED MSG="Event created"
```

### Key Metrics
- Events processed per second
- Queue depth (pending events)
- Active producers/workers
- System CPU/memory/disk
- Process uptime

## Failure Handling

### Process Death Detection
Manager polls PIDs every second and restarts dead processes.

### Graceful Shutdown
1. SIGTERM → processes finish current work
2. 5s timeout → SIGKILL
3. Cleanup: FIFOs, locks, PID files
4. State saved for next restart

### Emergency Cleanup
Force kills all project processes and removes all runtime files.
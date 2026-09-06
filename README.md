# Dynamic Data Structures: Building a Real-Time Social Media Feed

## Project Overview

This is an Operating Systems university project that demonstrates core OS concepts through a real-time social media feed simulator implemented in **Bash Shell Script**.

### Motivation

Operating Systems concepts are often taught theoretically. This project brings them to life by implementing a working system that demonstrates:
- Process management and multiprocessing
- Inter-process communication (IPC) via named pipes/FIFOs
- Producer-consumer problem with synchronization
- Mutual exclusion using flock
- Dynamic data structures in Bash
- File system operations and persistence
- Process lifecycle management
- Real-time event processing

### Problem Statement

Build a local real-time social media feed simulator where:
- Multiple producer processes generate social media events (posts, likes, comments, shares, follows)
- Events are queued in a thread-safe dynamic queue
- Multiple worker processes consume events and update a dynamic feed data structure
- All processes communicate via IPC (FIFOs)
- Shared resources are protected by mutual exclusion locks
- System state persists across restarts
- A frontend dashboard visualizes the feed, processes, queue, and statistics in real-time

### Objectives

1. Implement dynamic data structures (feed, queue, priority queue) in Bash
2. Create multiple concurrent producer and consumer processes
3. Implement FIFO-based IPC for inter-process communication
4. Use flock for synchronization and mutual exclusion
5. Manage process lifecycle (start, monitor, stop, cleanup)
6. Persist data to filesystem and restore on restart
7. Build a real-time frontend dashboard
8. Demonstrate all OS concepts clearly for instructor evaluation

### Features

- **Dynamic Feed**: Insert, delete, search, update, traverse posts
- **Event Queue**: Enqueue, dequeue, peek, size operations with FIFO semantics
- **Priority Queue**: High-priority events (notifications) processed first
- **Multiprocessing**: Real OS processes with actual PIDs
- **IPC**: Named pipes for producer-worker communication
- **Synchronization**: flock-based mutual exclusion for shared resources
- **Process Manager**: Start/stop/list processes, graceful shutdown
- **Persistence**: Users, posts, events, feed, statistics survive restart
- **Logging**: OS-style structured logs with timestamps, PIDs, status
- **Frontend Dashboard**: Real-time feed, process monitor, queue view, statistics, logs
- **Resource Monitoring**: CPU, memory, uptime, process count from /proc
- **Demo Mode**: One-command startup for instructor demonstration

### Technology Stack

| Layer | Technology |
|-------|------------|
| Backend Core | Bash Shell Script |
| IPC | Named Pipes (FIFOs) |
| Synchronization | flock |
| Data Storage | File System (JSON-like text files) |
| Frontend | HTML5 + CSS3 + Vanilla JavaScript |
| Process Management | Bash background processes, ps, kill, wait |
| Logging | Custom structured logger |

### Architecture

```
                    FRONTEND (HTML/CSS/JS)
                           │
                           ▼
                  LOCAL COMMAND LAYER
                           │
                           ▼
                    BASH BACKEND
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
   User Processes    Event Queue        Process Manager
        │                  │
        │                  ▼
        │            Worker Processes
        │                  │
        └──────────────────┤
                           ▼
                    Dynamic Feed
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
         Data Files                  Logs
```

### Directory Structure

```
project-root/
│
├── backend/
│   ├── main.sh
│   ├── config.sh
│   │
│   ├── processes/
│   │   ├── producer.sh
│   │   ├── worker.sh
│   │   ├── manager.sh
│   │   └── simulator.sh
│   │
│   ├── datastructures/
│   │   ├── queue.sh
│   │   ├── feed.sh
│   │   └── priority_queue.sh
│   │
│   ├── ipc/
│   │   └── fifo.sh
│   │
│   ├── synchronization/
│   │   └── locks.sh
│   │
│   ├── services/
│   │   ├── event_service.sh
│   │   ├── user_service.sh
│   │   ├── feed_service.sh
│   │   └── statistics_service.sh
│   │
│   ├── system/
│   │   ├── process_manager.sh
│   │   ├── resource_monitor.sh
│   │   └── cleanup.sh
│   │
│   └── utils/
│       ├── logger.sh
│       ├── validation.sh
│       └── common.sh
│
├── frontend/
│   ├── index.html
│   ├── css/
│   │   └── style.css
│   └── js/
│       └── app.js
│
├── data/
│   ├── users/
│   ├── posts/
│   ├── events/
│   ├── feed/
│   ├── queue/
│   └── stats/
│
├── logs/
│   ├── events.log
│   ├── workers.log
│   └── system.log
│
├── runtime/
│   ├── pids/
│   ├── locks/
│   └── pipes/
│
├── tests/
│
├── scripts/
│   ├── setup.sh
│   ├── build.sh
│   ├── run.sh
│   ├── stop.sh
│   └── clean.sh
│
├── docs/
│   ├── architecture.md
│   ├── os-concepts.md
│   ├── data-structures.md
│   ├── ipc.md
│   ├── synchronization.md
│   └── testing.md
│
├── .gitignore
└── README.md
```

### Installation

#### Fedora/Linux

```bash
# Clone the repository
git clone https://github.com/the-5ultan/real-time-social-media-feed.git
cd real-time-social-media-feed

# Make scripts executable
chmod +x scripts/*.sh
chmod +x backend/*.sh
chmod +x backend/**/*.sh

# Run setup
./scripts/setup.sh

# Start the system
./scripts/run.sh
```

#### Windows (WSL or Git Bash)

```bash
# Using WSL (Recommended)
wsl
cd /mnt/d/real-time-social-media-feed
chmod +x scripts/*.sh
chmod +x backend/*.sh
chmod +x backend/**/*.sh
./scripts/setup.sh
./scripts/run.sh

# Using Git Bash
cd D:/real-time-social-media-feed
./scripts/setup.sh
./scripts/run.sh
```

### Demonstration

For instructor demonstration:

```bash
./scripts/run.sh
```

Then:
1. Backend starts automatically
2. Open `frontend/index.html` in browser
3. Click "Start System" → "Start Simulation"
4. Observe: 3 producers, 2 workers with real PIDs
5. Watch events flow: Producer → Queue → Worker → Feed
6. Check Process Monitor: Actual PIDs, states, events processed
7. Check Event Queue: Size, pending events, priorities
8. Check Statistics: Real-time counts
9. Check Logs: Structured OS-style entries
10. Stop a worker → System detects and replaces it
11. Generate burst of events → Observe synchronization
12. Stop System → Graceful cleanup
13. Restart → Data persists

### Testing

```bash
# Run all tests
./scripts/test.sh

# Run specific test suites
./tests/test_datastructures.sh
./tests/test_queue.sh
./tests/test_ipc.sh
./tests/test_synchronization.sh
./tests/test_processes.sh
./tests/test_persistence.sh
./tests/test_stress.sh
```

### Operating Systems Concepts Demonstrated

| Concept | Implementation | Script |
|---------|---------------|--------|
| Process Management | Background processes with real PIDs, process manager | `backend/processes/manager.sh`, `backend/system/process_manager.sh` |
| Multiprocessing | Multiple concurrent producers/workers | `backend/processes/producer.sh`, `backend/processes/worker.sh` |
| IPC | Named pipes (FIFOs) for producer-worker communication | `backend/ipc/fifo.sh` |
| Producer-Consumer | Producers enqueue → Queue → Workers dequeue | `backend/processes/producer.sh`, `backend/processes/worker.sh`, `backend/datastructures/queue.sh` |
| Synchronization | flock on lock files for critical sections | `backend/synchronization/locks.sh` |
| Mutual Exclusion | Feed lock, queue lock, stats lock | `backend/synchronization/locks.sh` |
| Dynamic Data Structures | Linked-list-style feed, array-based queue in Bash | `backend/datastructures/feed.sh`, `backend/datastructures/queue.sh` |
| File System Operations | Persistent storage, atomic writes, recovery | `backend/services/*`, `backend/system/cleanup.sh` |
| Process Lifecycle | Start → Init → Run → Stop → Cleanup with trap | `backend/system/process_manager.sh`, `backend/system/cleanup.sh` |
| Resource Monitoring | /proc parsing for CPU, memory, uptime | `backend/system/resource_monitor.sh` |

### Documentation

- [Architecture](docs/architecture.md)
- [OS Concepts](docs/os-concepts.md)
- [Data Structures](docs/data-structures.md)
- [IPC](docs/ipc.md)
- [Synchronization](docs/synchronization.md)
- [Testing](docs/testing.md)

### Limitations

- Bash arrays have performance limits for large datasets
- No network distribution (single machine only)
- Frontend polling-based (not WebSocket)
- Priority queue is simplified (not heap-based)
- Windows support requires WSL/Git Bash

### Future Improvements

- Heap-based priority queue implementation
- WebSocket frontend for true real-time updates
- Process checkpointing for faster recovery
- Distributed version with multiple nodes
- Enhanced stress testing framework
- Configuration file for all parameters

### License

Educational project for Operating Systems course.
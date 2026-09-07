# Testing Documentation

This document describes the testing strategy, test suites, and how to run tests for the Real-Time Social Media Feed project.

## Test Philosophy

Testing follows the principle: **test behavior, not implementation**. Tests verify that the system correctly implements OS concepts and handles real-world scenarios.

## Test Structure

```
tests/
├── test.sh                 # Main test runner
├── test_datastructures.sh  # Data structure unit tests
├── test_queue.sh           # Queue-specific tests (to be created)
├── test_ipc.sh             # IPC tests (to be created)
├── test_synchronization.sh # Synchronization tests (to be created)
├── test_processes.sh       # Process management tests (to be created)
├── test_persistence.sh     # Persistence tests (to be created)
└── test_stress.sh          # Stress/load tests (to be created)
```

## Running Tests

### All Tests
```bash
./scripts/test.sh
```

### Individual Test Suites
```bash
# Data structures
./tests/test_datastructures.sh

# Future test suites (to be implemented)
./tests/test_queue.sh
./tests/test_ipc.sh
./tests/test_synchronization.sh
./tests/test_processes.sh
./tests/test_persistence.sh
./tests/test_stress.sh
```

### With Verbose Output
```bash
LOG_LEVEL=DEBUG ./scripts/test.sh
```

## Test Categories

### 1. Unit Tests (Data Structures)

**File**: `tests/test_datastructures.sh`

**Coverage**:
- Feed: init, add, remove, find, search, traverse, pagination
- Queue: init, enqueue, dequeue, peek, size, filter, clear
- Priority Queue: init, enqueue, dequeue, peek, priority ordering

**Run**:
```bash
bash tests/test_datastructures.sh
```

**Expected Output**:
```
Testing feed...
Initial size: 0
After add: 1
Feed: [{"post_id":"post_1",...}]
Testing queue...
Initial size: 0
After enqueue: 1
Peek: {"event_id":"evt_1",...}
After dequeue: 0
Testing priority queue...
Initial size: 0
After enqueue: 1
Peek: {"event_id":"evt_1",...}
After dequeue: 0
All tests passed!
```

### 2. Integration Tests (Test Runner)

**File**: `scripts/test.sh`

**Coverage**:
| Test Suite | Description |
|------------|-------------|
| Data Structures | Feed, Queue, Priority Queue operations |
| Services | User, Event, Feed, Statistics services |
| IPC (FIFO) | FIFO creation, write/read, cleanup |
| Synchronization | Lock acquire/release, try-lock, force-release |
| Process Management | Start/stop/monitor producers and workers |
| Persistence | Save/restore state, crash recovery |
| Cleanup | Runtime cleanup, pre-start cleanup |
| Validation | Input validation for all data types |
| Logger | All log levels, categories, rotation |
| Resource Monitor | CPU, memory, disk, uptime, processes |

**Run**:
```bash
./scripts/test.sh
```

**Expected Output**:
```
╔══════════════════════════════════════════════════════════════╗
║  Real-Time Social Media Feed - Test Suite                    ║
╚══════════════════════════════════════════════════════════════╝

[TEST] Running Data Structures...
[PASS] Data Structures passed
[TEST] Running Services...
[PASS] Services passed
[TEST] Running IPC (FIFO)...
[PASS] IPC (FIFO) passed
[TEST] Running Synchronization (flock)...
[PASS] Synchronization (flock) passed
[TEST] Running Process Management...
[PASS] Process Management passed
[TEST] Running Persistence...
[PASS] Persistence passed
[TEST] Running Cleanup...
[PASS] Cleanup passed
[TEST] Running Validation...
[PASS] Validation passed
[TEST] Running Logger...
[PASS] Logger passed
[TEST] Running Resource Monitor...
[PASS] Resource Monitor passed
[TEST] Running Existing Data Structures Test...
[PASS] Existing Data Structures Test passed

╔══════════════════════════════════════════════════════════════╗
║  TEST SUMMARY                                                ║
╠══════════════════════════════════════════════════════════════╣
║  Total:   11                                                 ║
║  Passed:  11                                                 ║
║  Failed:  0                                                  ║
╚══════════════════════════════════════════════════════════════╝

[SUCCESS] All tests passed!
```

## Test Implementation Patterns

### Inline Test Functions (in test.sh)
```bash
test_datastructures() {
    source config.sh
    source utils/common.sh
    source datastructures/feed.sh
    source datastructures/queue.sh
    source datastructures/priority_queue.sh
    
    feed_init
    [[ $(feed_size) -eq 0 ]] || return 1
    
    local post1=$(json_object "post_id" "test_1" ...)
    feed_add_post "$post1"
    [[ $(feed_size) -eq 1 ]] || return 1
    
    # ... more assertions
    
    return 0
}
```

### External Test Files
```bash
#!/usr/bin/env bash
# tests/test_datastructures.sh

source backend/config.sh
source backend/utils/common.sh
source backend/datastructures/feed.sh
source backend/datastructures/queue.sh
source backend/datastructures/priority_queue.sh

# Test feed
feed_init
echo "Initial size: $(feed_size)"
post1=$(json_object "post_id" "post_1" ...)
feed_add_post "$post1"
echo "After add: $(feed_size)"
echo "Feed: $(feed_get_all)"
```

### Test Helpers
```bash
# Assertion helpers
assert_equal() {
    [[ "$1" == "$2" ]] || { echo "Expected: $2, Got: $1"; return 1; }
}

assert_not_empty() {
    [[ -n "$1" ]] || { echo "Expected non-empty"; return 1; }
}

assert_json_field() {
    local json="$1"
    local field="$2"
    local expected="$3"
    local actual=$(echo "$json" | jq -r ".$field")
    [[ "$actual" == "$expected" ]] || return 1
}
```

## Test Scenarios

### 1. Data Structure Operations

#### Feed Tests
- [ ] Initialize empty feed
- [ ] Add post to empty feed
- [ ] Add multiple posts (newest first)
- [ ] Find post by ID
- [ ] Search posts by content (case-insensitive)
- [ ] Search posts by user
- [ ] Get all posts
- [ ] Get paginated posts
- [ ] Update post (likes, comments, shares)
- [ ] Add comment to post
- [ ] Remove post
- [ ] Feed statistics
- [ ] Max size enforcement

#### Queue Tests
- [ ] Initialize empty queue
- [ ] Enqueue single event
- [ ] Enqueue multiple events
- [ ] Dequeue returns oldest (FIFO)
- [ ] Peek front without removing
- [ ] Peek rear
- [ ] Get all events
- [ ] Filter by event type
- [ ] Filter by priority
- [ ] Remove specific event by ID
- [ ] Clear queue
- [ ] Size and empty checks
- [ ] Full queue handling

#### Priority Queue Tests
- [ ] Initialize empty priority queue
- [ ] Enqueue events with different priorities
- [ ] Dequeue returns highest priority (lowest number)
- [ ] Same priority maintains FIFO order
- [ ] Peek highest priority
- [ ] Size by priority
- [ ] Clear priority queue

### 2. Service Tests

#### User Service
- [ ] Create user
- [ ] Get user by ID
- [ ] Get user by username
- [ ] Get all users
- [ ] Get random user
- [ ] Update user stats (followers, following, posts)
- [ ] Search users
- [ ] Duplicate username rejection

#### Event Service
- [ ] Create POST event
- [ ] Create LIKE event
- [ ] Create COMMENT event
- [ ] Create SHARE event
- [ ] Create FOLLOW event
- [ ] Create NOTIFICATION event
- [ ] Queue event (regular and priority)
- [ ] Process event updates feed/stats
- [ ] Event status transitions
- [ ] Get recent events

#### Statistics Service
- [ ] Initialize statistics
- [ ] Increment counters
- [ ] Decrement counters
- [ ] Set gauge values
- [ ] Get all statistics
- [ ] Display formatting
- [ ] Processing rate calculation
- [ ] Uptime tracking

### 3. IPC Tests

- [ ] Create all FIFOs
- [ ] Write to FIFO with timeout
- [ ] Read from FIFO with timeout
- [ ] Non-existent FIFO handling
- [ ] Multiple writers
- [ ] Broadcast to control FIFO
- [ ] FIFO cleanup

### 4. Synchronization Tests

- [ ] Acquire and release lock
- [ ] Timeout on lock acquisition
- [ ] Try lock (non-blocking)
- [ ] Check if lock held
- [ ] With_lock executes atomically
- [ ] Force release lock
- [ ] List all locks
- [ ] Concurrent access protection

### 5. Process Management Tests

- [ ] Start producer
- [ ] Start worker
- [ ] Stop producer
- [ ] Stop worker
- [ ] List processes
- [ ] Get process status
- [ ] Monitor dead process restart
- [ ] Scale producers/workers
- [ ] Graceful shutdown

### 6. Persistence Tests

- [ ] Save state (stats, queue, feed, PIDs)
- [ ] Restore state
- [ ] Data survives restart
- [ ] Atomic writes
- [ ] Corrupted file handling

### 7. Stress Tests (Future)

- [ ] High event throughput (1000+ events/sec)
- [ ] Many concurrent producers (10)
- [ ] Many concurrent workers (10)
- [ ] Queue near capacity
- [ ] Long-running stability (1 hour)
- [ ] Memory usage under load
- [ ] Lock contention under load

## Continuous Integration

### GitHub Actions (Example)
```yaml
# .github/workflows/test.yml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y jq
      - name: Make scripts executable
        run: chmod +x scripts/*.sh backend/**/*.sh
      - name: Run tests
        run: ./scripts/test.sh
```

### Pre-commit Hooks
```bash
# .git/hooks/pre-commit
#!/bin/bash
./scripts/test.sh || exit 1
```

## Test Data Management

### Test Isolation
Each test should:
1. Use unique IDs (timestamp + random)
2. Clean up after itself
3. Not depend on other tests

```bash
# Good: unique IDs
local test_id=$(generate_id "test_")
feed_add_post "$(json_object "post_id" "$test_id" ...)"

# Cleanup
feed_remove_post "$test_id"
```

### Test Fixtures
```bash
# Create test user
create_test_user() {
    create_user "testuser_$(generate_id "u_")"
}

# Create test post
create_test_post() {
    local user_id="$1"
    create_post_event "$user_id" "TestUser" "Test content $(generate_id)"
}
```

## Debugging Tests

### Verbose Mode
```bash
LOG_LEVEL=DEBUG ./scripts/test.sh
```

### Run Single Test with Debug
```bash
LOG_LEVEL=DEBUG bash -c '
    source backend/config.sh
    source backend/utils/common.sh
    source backend/datastructures/feed.sh
    feed_init
    feed_add_post "$(json_object "post_id" "debug_1" ...)"
    echo "Feed: $(feed_get_all)"
'
```

### Inspect Test Artifacts
```bash
# After test run, check data files
cat data/feed/feed.json | jq .
cat data/queue/event_queue.json | jq .
cat data/stats/statistics.json | jq .
cat logs/system.log
```

## Test Coverage Goals

| Component | Target Coverage | Current |
|-----------|----------------|---------|
| Data Structures | 90% | ~70% |
| Services | 80% | ~60% |
| IPC | 80% | ~50% |
| Synchronization | 85% | ~60% |
| Process Management | 75% | ~50% |
| Persistence | 80% | ~50% |
| Overall | 80% | ~55% |

## Adding New Tests

1. **Add test function** to `scripts/test.sh`
2. **Follow naming convention**: `test_<component>()`
3. **Add to main()** test execution list
4. **Document in this file** under Test Scenarios
5. **Run and verify** passes consistently

## Troubleshooting Tests

### Common Failures

| Error | Cause | Fix |
|-------|-------|-----|
| "jq: command not found" | Missing dependency | `apt-get install jq` |
| "Permission denied" | Scripts not executable | `chmod +x scripts/*.sh backend/**/*.sh` |
| "FIFO already exists" | Previous run didn't clean | `./scripts/clean.sh -f` |
| "Lock timeout" | Deadlock or slow test | Increase timeout or check lock order |
| "Process already running" | Previous test didn't stop | `./scripts/stop.sh` before test |

### Flaky Test Mitigation
- Add small delays (`sleep 0.1`) between async operations
- Use unique IDs to avoid collisions
- Clean up thoroughly in test teardown
- Run tests in isolation when debugging

## Performance Benchmarks

### Baseline Metrics (Target)
| Operation | Target Time | Current |
|-----------|-------------|---------|
| Feed add post | < 10ms | ~5ms |
| Queue enqueue | < 5ms | ~3ms |
| Queue dequeue | < 10ms | ~5ms |
| Stats increment | < 5ms | ~3ms |
| User create | < 20ms | ~10ms |
| Event process | < 50ms | ~30ms |

### Stress Test Commands
```bash
# Generate load
for i in {1..1000}; do
    ./scripts/api_server.py &
    # Use curl or frontend to generate events
done
```
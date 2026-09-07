# Synchronization Documentation

This document describes the synchronization mechanisms implemented in the Real-Time Social Media Feed project, focusing on mutual exclusion using `flock`.

## Overview

The system uses `flock` (file locking) for all synchronization needs. Locks are implemented as files in `runtime/locks/` with each shared resource having its dedicated lock file.

## Lock Architecture

### Lock Files
| Lock Name | File Path | Protects |
|-----------|-----------|----------|
| feed | `runtime/locks/feed.lock` | Feed data structure (add/remove/update posts) |
| queue | `runtime/locks/queue.lock` | Event queue and priority queue |
| stats | `runtime/locks/stats.lock` | Statistics counters |
| users | `runtime/locks/users.lock` | User data (create/update) |

### Lock Implementation

```bash
# Low-level lock functions in synchronization/locks.sh

# Acquire exclusive lock with timeout
lock_acquire() {
    local lock_name="$1"
    local timeout="${2:-10}"
    local lock_file="${LOCKS_DIR}/${lock_name}.lock"
    
    touch "$lock_file"  # Ensure exists
    
    local count=0
    # flock -x = exclusive, -n = non-blocking
    while ! flock -x -n 200 2>/dev/null; do
        [[ $count -ge $timeout ]] && return 1
        sleep 1
        ((count++))
    done
    return 0
}

# Release lock
lock_release() {
    flock -u 200 2>/dev/null
}

# Execute command with automatic lock acquisition/release
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

### Predefined Lock Helpers

```bash
# Resource-specific lock functions
feed_lock() { with_lock "feed" "$@"; }
queue_lock() { with_lock "queue" "$@"; }
stats_lock() { with_lock "stats" "$@"; }
users_lock() { with_lock "users" "$@"; }

# Convenience aliases
feed_critical() { feed_lock "$@"; }
queue_critical() { queue_lock "$@"; }
stats_critical() { stats_lock "$@"; }
users_critical() { users_lock "$@"; }
```

## Usage in Data Structures

### Feed Operations
```bash
feed_add_post() {
    local post_json="$1"
    
    (
        flock -x 200
        local content=$(read_file "$feed_file")
        local new_feed=$(echo "$content" | jq --argjson post "$post_json" '[$post] + .')
        new_feed=$(echo "$new_feed" | jq --argjson max "$FEED_MAX_POSTS" '.[:$max]')
        atomic_write "$feed_file" "$new_feed"
    ) 200>"$FEED_LOCK"
}

feed_remove_post() {
    local post_id="$1"
    
    (
        flock -x 200
        local content=$(read_file "$feed_file")
        local new_feed=$(echo "$content" | jq --arg pid "$post_id" 'map(select(.post_id != $pid))')
        atomic_write "$feed_file" "$new_feed"
    ) 200>"$FEED_LOCK"
}

feed_update_post() {
    local post_id="$1"
    local updates_json="$2"
    
    (
        flock -x 200
        local content=$(read_file "$feed_file")
        local new_feed=$(echo "$content" | jq --arg pid "$post_id" --argjson updates "$updates_json" '
            map(if .post_id == $pid then . + $updates else . end)
        ')
        atomic_write "$feed_file" "$new_feed"
    ) 200>"$FEED_LOCK"
}
```

### Queue Operations
```bash
queue_enqueue() {
    (
        flock -x 200
        if queue_is_full; then return 1; fi
        local content=$(read_file "$queue_file")
        local new_queue=$(echo "$content" | jq --argjson event "$event_json" '. + [$event]')
        atomic_write "$queue_file" "$new_queue"
    ) 200>"$QUEUE_LOCK"
}

queue_dequeue() {
    (
        flock -x 200
        local content=$(read_file "$queue_file")
        local event_json=$(echo "$content" | jq '.[0]')
        local new_queue=$(echo "$content" | jq '.[1:]')
        atomic_write "$queue_file" "$new_queue"
        echo "$event_json"
    ) 200>"$QUEUE_LOCK"
}
```

### Statistics Operations
```bash
stats_increment() {
    local field="$1"
    local increment="${2:-1}"
    
    (
        flock -x 200
        local stats_json=$(read_file "$STATS_FILE")
        local new_stats=$(echo "$stats_json" | jq --arg f "$field" --argjson inc "$increment" '.[$f] += $inc')
        atomic_write "$STATS_FILE" "$new_stats"
    ) 200>"$STATS_LOCK"
}
```

### User Operations
```bash
create_user() {
    (
        flock -x 200
        atomic_write "${USERS_DIR}/${user_id}.json" "$user_json"
        local users_index=$(read_file "$USERS_FILE")
        local new_index=$(echo "$users_index" | jq --argjson user "$user_json" '. + [$user]')
        atomic_write "$USERS_FILE" "$new_index"
    ) 200>"$USERS_LOCK"
}
```

## Advanced Lock Features

### Non-blocking Try Lock
```bash
lock_try() {
    local lock_name="$1"
    local lock_file="${LOCKS_DIR}/${lock_name}.lock"
    touch "$lock_file"
    
    if flock -x -n 200 2>/dev/null; then
        return 0  # Acquired
    else
        return 1  # Not available
    fi
} 200>"${LOCKS_DIR}/${lock_name}.lock"
```

### Check if Lock Held
```bash
lock_is_held() {
    local lock_name="$1"
    local lock_file="${LOCKS_DIR}/${lock_name}.lock"
    
    if flock -x -n 200 2>/dev/null; then
        flock -u 200
        return 1  # Not held (we acquired and released)
    else
        return 0  # Held by another process
    fi
} 200>"$lock_file"
```

### Lock Information
```bash
lock_info() {
    local lock_name="$1"
    local lock_file="${LOCKS_DIR}/${lock_name}.lock"
    
    local held="false"
    lock_is_held "$lock_name" && held="true"
    
    json_object \
        "name" "$lock_name" \
        "file" "$lock_file" \
        "held" "$held"
}

lock_list() {
    # Lists all locks with status
}
```

### Emergency Force Release
```bash
lock_force_release() {
    local lock_name="$1"
    local lock_file="${LOCKS_DIR}/${lock_name}.lock"
    rm -f "$lock_file"  # Remove lock file entirely
    log_warn "SYNC" "Force released lock: $lock_name"
}
```

### Cleanup All Locks
```bash
lock_cleanup_all() {
    rm -f "${LOCKS_DIR}"/*.lock
}
```

## Locking Patterns

### Pattern 1: Simple Critical Section
```bash
with_lock "feed" bash -c '
    feed_add_post "$post_json"
'
```

### Pattern 2: Manual Acquire/Release
```bash
feed_lock_acquire
# ... multiple operations ...
feed_lock_release
```

### Pattern 3: Check-Then-Act (with lock)
```bash
# WRONG - race condition
if queue_is_empty; then
    # Another process might add event here
    queue_enqueue "$event"
fi

# CORRECT - atomic check-and-act
queue_lock bash -c '
    if queue_is_empty; then
        queue_enqueue "$event"
    fi
'
```

### Pattern 4: Read-Modify-Write
```bash
# All read-modify-write operations must hold lock
stats_lock bash -c '
    local current=$(stats_get "counter")
    stats_set "counter" $((current + 1))
'
```

## Deadlock Prevention

### Lock Ordering
Always acquire locks in consistent order:
```bash
# GOOD: Consistent order (feed → queue → stats)
feed_lock bash -c '
    queue_lock bash -c '
        stats_lock bash -c '
            # All three locks held
        '
    '
'

# BAD: Different orders in different places
# Process A: feed → queue
# Process B: queue → feed  → DEADLOCK!
```

### Timeout on Acquisition
```bash
lock_acquire "feed" 10  # 10 second timeout
# Returns 1 if timeout, preventing indefinite wait
```

### Lock Scope Minimization
- Hold locks for shortest time possible
- Do computation OUTSIDE lock when possible
- Only protect the actual shared resource access

```bash
# GOOD: Compute outside lock
local new_value=$(compute_expensive_thing)
stats_lock bash -c "
    stats_set 'field' '$new_value'
"

# BAD: Compute inside lock (blocks others)
stats_lock bash -c "
    local new_value=$(compute_expensive_thing)
    stats_set 'field' '$new_value'
"
```

## Lock Debugging and Monitoring

### View Lock Status
```bash
# From frontend or CLI
lock_list
# Returns: [{"name":"feed","file":"/.../feed.lock","held":false}, ...]
```

### Log Lock Events
```bash
log_sync() {
    local lock_name="$1"
    local action="$2"  # ACQUIRE, RELEASE, WAIT, TIMEOUT
    local pid="${3:-$$}"
    local message="$4"
    
    _log $LOG_LVL_DEBUG "SYNC" "$message" "$pid" "sync" "" "" "LOCK=$lock_name ACTION=$action"
}
```

### Log Output Example
```
[2026-09-07 10:30:00] PID=12345 USER=sync CATEGORY=SYNC LEVEL=DEBUG LOCK=feed ACTION=ACQUIRE MSG="Lock acquired for command: feed_add_post"
[2026-09-07 10:30:00] PID=12345 USER=sync CATEGORY=SYNC LEVEL=DEBUG LOCK=feed ACTION=RELEASE MSG="Lock released after command"
```

## Performance Characteristics

### Lock Contention
| Scenario | Expected Contention | Mitigation |
|----------|---------------------|------------|
| High producer rate | Queue lock | Batch enqueue, increase poll interval |
| High worker rate | Queue lock | Priority queue for critical events |
| Frequent stats updates | Stats lock | Batch increments, async flush |
| Feed reads | None (lock-free) | N/A |

### Benchmark Results (Approximate)
- Lock acquisition: ~0.1-0.5ms (uncontended)
- Lock acquisition: ~1-10ms (contended, with timeout)
- Critical section (feed add): ~2-5ms
- Critical section (queue dequeue): ~1-3ms

## Comparison: flock vs Alternatives

| Mechanism | Pros | Cons | Used Here |
|-----------|------|------|-----------|
| flock | POSIX, automatic release on close, works on NFS | File-based, requires filesystem | ✅ Primary |
| mutex (pthread) | Fast, in-memory | Not available in Bash | ❌ |
| semaphores | Counting, inter-process | Complex, not in Bash | ❌ |
| lockfile (mkdir) | Atomic create | No timeout, stale on crash | ❌ |
| flock (this impl) | Automatic cleanup, timeout, debug | File I/O overhead | ✅ |

## Testing Synchronization

### Concurrent Access Test
```bash
# Run multiple writers concurrently
for i in {1..10}; do
    (
        for j in {1..100}; do
            stats_increment "test_counter"
        done
    ) &
done
wait

# Final count should be 1000
stats_get "test_counter"  # → 1000
```

### Lock Timeout Test
```bash
# Hold lock in background
(
    lock_acquire "test_lock"
    sleep 5
    lock_release "test_lock"
) &

# Try to acquire with timeout
lock_acquire "test_lock" 2  # Should timeout after 2s
# Returns 1
```

### Deadlock Detection
```bash
# Monitor for processes stuck on locks
ps aux | grep -E "(flock|bash.*lock)"
```

## Best Practices Summary

1. **Always use `with_lock`** for simple critical sections
2. **Acquire locks in consistent order** (feed → queue → stats → users)
3. **Minimize critical section duration** - compute outside
4. **Use timeouts** - `lock_acquire "name" 10`
5. **Log lock events** - enables debugging
6. **Clean up on exit** - `trap` handlers call `lock_cleanup_all`
7. **Validate after changes** - `validate_feed`, `validate_queue`
8. **Force release only in emergencies** - can cause corruption

## Troubleshooting

### Stale Lock Files
```bash
# Check for locks held by dead processes
for lock in runtime/locks/*.lock; do
    if ! flock -x -n 200 2>/dev/null < "$lock"; then
        echo "Lock $(basename $lock) is held"
    fi
done

# Force clean
lock_cleanup_all
```

### Process Stuck on Lock
```bash
# Find process holding lock
lsof runtime/locks/feed.lock

# Kill if necessary
kill -TERM <PID>
```

### Permission Issues
```bash
# Ensure lock directory is writable
ls -la runtime/locks/
# Should be owned by running user, mode 755
```
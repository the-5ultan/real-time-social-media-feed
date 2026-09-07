# Data Structures Documentation

This document details the dynamic data structures implemented in the Real-Time Social Media Feed project.

## Overview

All data structures are implemented in pure Bash using JSON files for persistence and `flock` for thread safety. The structures support the required operations: Insert, Delete, Search, Update, Traverse, and Count.

---

## 1. Dynamic Feed (`backend/datastructures/feed.sh`)

### Data Model
```json
{
  "post_id": "post_1234567890_1234",
  "event_id": "evt_1234567890_1234",
  "user_id": "user_ali",
  "username": "Ali",
  "content": "Hello world!",
  "timestamp": "2026-09-07 10:30:00",
  "likes": 5,
  "comments": 2,
  "shares": 1,
  "comments_data": [
    {
      "comment_id": "cmt_1234567890_1234",
      "event_id": "evt_1234567890_1234",
      "user_id": "user_ahmed",
      "username": "Ahmed",
      "content": "Great post!",
      "timestamp": "2026-09-07 10:31:00"
    }
  ]
}
```

### Storage
- File: `data/feed/feed.json`
- Format: JSON array (newest first, index 0 = most recent)
- Max size: 1000 posts (configurable via `FEED_MAX_POSTS`)

### Operations

| Operation | Function | Complexity | Description |
|-----------|----------|------------|-------------|
| Initialize | `feed_init()` | O(1) | Creates empty array file |
| Insert | `feed_add_post()` | O(1)* | Prepend to array, trim to max |
| Delete | `feed_remove_post()` | O(n) | Filter by post_id |
| Update | `feed_update_post()` | O(n) | Map and merge updates |
| Search by ID | `feed_find_post()` | O(n) | Find single post |
| Search by Content | `feed_search_posts()` | O(n) | Case-insensitive substring |
| Search by User | `feed_search_by_user()` | O(n) | Filter by user_id |
| Traverse All | `feed_get_all()` | O(1) | Return entire array |
| Paginate | `feed_get_page()` | O(1) | Slice with offset/limit |
| Count | `feed_size()` | O(1) | Array length |

*Insert at front is O(1) for JSON array prepend via `jq`

### Thread Safety
```bash
feed_add_post() {
    (
        flock -x 200
        # Critical section: read, modify, atomic_write
    ) 200>"$FEED_LOCK"
}
```

### Specialized Operations
```bash
feed_increment_likes()      # Atomic like counter increment
feed_decrement_likes()      # Atomic like counter decrement
feed_increment_comments()   # Atomic comment counter increment
feed_increment_shares()     # Atomic share counter increment
feed_add_comment()          # Add comment to comments_data array
feed_get_stats()            # Aggregate statistics
```

---

## 2. Event Queue (`backend/datastructures/queue.sh`)

### Data Model
```json
{
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
}
```

### Storage
- File: `data/queue/event_queue.json`
- Format: JSON array (FIFO: index 0 = front/oldest, last = rear/newest)
- Max size: 10000 events (configurable via `QUEUE_MAX_SIZE`)

### Operations

| Operation | Function | Complexity | Description |
|-----------|----------|------------|-------------|
| Initialize | `queue_init()` | O(1) | Creates empty array file |
| Enqueue | `queue_enqueue()` | O(1)* | Append to rear |
| Dequeue | `queue_dequeue()` | O(n) | Shift from front |
| Peek Front | `queue_peek()` | O(1) | View front without removing |
| Peek Rear | `queue_peek_rear()` | O(1) | View rear without removing |
| Get All | `queue_get_all()` | O(1) | Return entire array (with limit) |
| Filter by Type | `queue_get_by_type()` | O(n) | Filter by event_type |
| Filter by Priority | `queue_get_by_priority()` | O(n) | Filter by priority |
| Remove by ID | `queue_remove_event()` | O(n) | Filter out specific event |
| Clear | `queue_clear()` | O(1) | Reset to empty array |
| Size | `queue_size()` | O(1) | Array length |
| Empty Check | `queue_is_empty()` | O(1) | Size == 0 |
| Full Check | `queue_is_full()` | O(1) | Size >= max |

*Enqueue is O(1) for JSON array append via `jq`

### Thread Safety
```bash
queue_enqueue() {
    (
        flock -x 200
        if queue_is_full; then return 1; fi
        # Read, append, atomic_write
    ) 200>"$QUEUE_LOCK"
}
```

### Statistics
```bash
queue_get_stats() {
    # Returns: { size, by_type: {...}, by_priority: {...} }
}
```

---

## 3. Priority Queue (`backend/datastructures/priority_queue.sh`)

### Data Model
```json
{
  "1": [  // Priority 1 (highest) - NOTIFICATION
    { "event_id": "...", "priority": 1, ... }
  ],
  "2": [  // Priority 2 - COMMENT
    { "event_id": "...", "priority": 2, ... }
  ],
  "5": [  // Priority 5 - POST
    { "event_id": "...", "priority": 5, ... }
  ]
}
```

### Storage
- File: `data/queue/priority_queue.json`
- Format: JSON object with priority keys (strings), each containing array
- Uses same lock as regular queue (`QUEUE_LOCK`)

### Priority Levels (Lower = Higher Priority)
| Priority | Event Type | Constant |
|----------|------------|----------|
| 1 | NOTIFICATION | `PRIORITY_NOTIFICATION` |
| 2 | COMMENT | `PRIORITY_COMMENT` |
| 3 | SHARE | `PRIORITY_SHARE` |
| 4 | LIKE | `PRIORITY_LIKE` |
| 5 | POST | `PRIORITY_POST` |
| 6 | FOLLOW | `PRIORITY_FOLLOW` |

### Operations

| Operation | Function | Complexity | Description |
|-----------|----------|------------|-------------|
| Initialize | `pqueue_init()` | O(1) | Creates empty object file |
| Enqueue | `pqueue_enqueue()` | O(1)* | Append to priority bucket |
| Dequeue | `pqueue_dequeue()` | O(p) | Find lowest non-empty priority, shift |
| Peek | `pqueue_peek()` | O(p) | View highest priority event |
| Get All | `pqueue_get_all()` | O(1) | Return entire object |
| Size by Priority | `pqueue_size_by_priority()` | O(p) | Count per priority |
| Clear | `pqueue_clear()` | O(1) | Reset to empty object |
| Size | `pqueue_size()` | O(p) | Sum of all bucket lengths |
| Empty Check | `pqueue_is_empty()` | O(p) | Total size == 0 |

*O(p) where p = number of priority levels (typically 6)

### Dequeue Algorithm
```bash
pqueue_dequeue() {
    (
        flock -x 200
        # 1. Find highest priority (lowest number) with events
        local priority=$(echo "$content" | jq -r '
            keys_unsorted | map(tonumber) | sort | .[] 
            | select(.[tostring] | length > 0) | tostring' | head -1)
        
        # 2. Get first event from that priority bucket
        event_json=$(echo "$content" | jq --arg pri "$priority" '.[$pri][0]')
        
        # 3. Remove it from bucket
        # 4. If bucket empty, delete priority key
    ) 200>"$QUEUE_LOCK"
}
```

### Statistics
```bash
pqueue_get_stats() {
    # Returns: { total_size, by_priority: {...}, by_type: {...} }
}
```

---

## 4. Comparison and Usage Guidelines

### When to Use Each Structure

| Scenario | Structure | Reason |
|----------|-----------|--------|
| Social media feed (newest first) | Feed | Optimized for prepend, search by user/content |
| Event processing (FIFO order) | Queue | Fair ordering, simple semantics |
| High-priority events first | Priority Queue | Notifications processed before posts |

### Integration with Services

**Event Service uses both queues:**
```bash
queue_event() {
    if [[ "$use_priority" == "true" ]]; then
        pqueue_enqueue "$queued_json"
    else
        queue_enqueue "$queued_json"
    fi
}
```

**Workers can use either:**
```bash
# In worker.sh
if [[ "$USE_PRIORITY_QUEUE" == "true" ]]; then
    event_json=$(pqueue_dequeue)
else
    event_json=$(queue_dequeue)
fi
```

### Performance Considerations

1. **JSON Parsing Overhead**: Each operation uses `jq` which spawns a process
2. **File I/O**: Every write uses `atomic_write` (temp file + mv)
3. **Lock Contention**: High concurrency may cause lock wait times
4. **Memory**: Entire structure loaded into memory for each operation

### Optimization Opportunities

1. **Batch Operations**: Process multiple events per lock acquisition
2. **In-Memory Cache**: Keep hot data in memory, flush periodically
3. **Index Files**: Maintain separate index for O(1) lookups
4. **Binary Format**: Use more efficient serialization than JSON

---

## 5. Persistence and Recovery

### Save State (on shutdown)
```bash
save_state() {
    feed_get_all > "${FEED_DIR}/state_feed.json"
    queue_get_all > "${QUEUE_DIR}/state_queue.json"
    pqueue_get_all > "${QUEUE_DIR}/state_priority_queue.json"
}
```

### Restore State (on startup)
```bash
restore_state() {
    [[ -f "${QUEUE_DIR}/state_queue.json" ]] && \
        cp "${QUEUE_DIR}/state_queue.json" "$QUEUE_FILE"
    [[ -f "${QUEUE_DIR}/state_priority_queue.json" ]] && \
        cp "${QUEUE_DIR}/state_priority_queue.json" "$PRIORITY_QUEUE_FILE"
    # Feed is always persistent (never cleared)
}
```

---

## 6. Testing

### Test Coverage
```bash
# From tests/test_datastructures.sh
feed_init
feed_add_post "$post1"
feed_size              # → 1
feed_find_post "id"    # → post object
feed_get_all           # → all posts

queue_init
queue_enqueue "$event1"
queue_peek             # → event
queue_dequeue          # → event
queue_size             # → 0

pqueue_init
pqueue_enqueue "$high_pri_event"
pqueue_enqueue "$low_pri_event"
pqueue_dequeue         # → high priority first
```

### Validation
```bash
validate_feed()    # Checks JSON structure and post validity
validate_queue()   # Checks JSON structure and event validity
validate_all_data() # Validates all data files
```

---

## 7. Configuration

| Parameter | Default | File |
|-----------|---------|------|
| `FEED_MAX_POSTS` | 1000 | config.sh |
| `QUEUE_MAX_SIZE` | 10000 | config.sh |
| `FEED_FILE` | data/feed/feed.json | config.sh |
| `QUEUE_FILE` | data/queue/event_queue.json | config.sh |
| `PRIORITY_QUEUE_FILE` | data/queue/priority_queue.json | config.sh |
| `FEED_LOCK` | runtime/locks/feed.lock | config.sh |
| `QUEUE_LOCK` | runtime/locks/queue.lock | config.sh |
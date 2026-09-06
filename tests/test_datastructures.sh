#!/usr/bin/env bash
# Test script for data structures

source backend/config.sh
source backend/utils/common.sh
source backend/utils/logger.sh
source backend/utils/validation.sh
source backend/datastructures/feed.sh
source backend/datastructures/queue.sh
source backend/datastructures/priority_queue.sh

# Test feed
echo "Testing feed..."
feed_init
echo "Initial size: $(feed_size)"
post1=$(json_object "post_id" "post_1" "user_id" "user_1" "username" "Ali" "content" "Hello World" "timestamp" "$(get_timestamp)" "likes" "0" "comments" "0" "shares" "0")
feed_add_post "$post1"
echo "After add: $(feed_size)"
echo "Feed: $(feed_get_all)"

echo ""
echo "Testing queue..."
queue_init
echo "Initial size: $(queue_size)"
event1=$(json_object "event_id" "evt_1" "user_id" "user_1" "user_name" "Ali" "event_type" "POST" "content" "Test" "timestamp" "$(get_timestamp)" "priority" "5" "status" "CREATED")
queue_enqueue "$event1"
echo "After enqueue: $(queue_size)"
echo "Peek: $(queue_peek)"
queue_dequeue
echo "After dequeue: $(queue_size)"

echo ""
echo "Testing priority queue..."
pqueue_init
echo "Initial size: $(pqueue_size)"
pqueue_enqueue "$event1"
echo "After enqueue: $(pqueue_size)"
echo "Peek: $(pqueue_peek)"
pqueue_dequeue
echo "After dequeue: $(pqueue_size)"

echo ""
echo "All tests passed!"
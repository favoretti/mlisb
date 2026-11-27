# 2. Transactional outbox

Status: accepted

## Context

The API wrote the order and then published `order.created`. A crash between the two left orders
that no worker ever saw.

## Decision

The API writes the event to an `outbox` table in the same transaction as the order. A relay reads
unpublished rows in id order and publishes them to the event bus.

## Consequences

- No event is lost when the API crashes.
- Workers can see an event more than once, so each of them must handle duplicates.
- Publishing lags the write by the relay's polling interval.

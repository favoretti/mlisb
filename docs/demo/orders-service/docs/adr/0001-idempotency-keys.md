# 1. Idempotency keys on checkout

Status: accepted

## Context

Mobile clients retry a checkout when the network drops, and some retried twice before the first
request finished. Customers were charged twice.

## Decision

Every checkout carries an `Idempotency-Key` header. The API stores the key with the receipt it
produced and returns that receipt for any repeat within 24 hours.

## Consequences

- A retry is always safe for the client.
- The `idempotency_keys` table grows with traffic; a nightly job removes keys older than a day.

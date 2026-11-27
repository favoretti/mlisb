# Changelog

## 2.4.0

- Checkouts go through the transactional outbox.
- The relay replaces the old poller behind `relay.enabled`.

## 2.3.1

- Idempotency keys expire after 24 hours instead of 7 days.

# Rollout plan

## Phase 1: shadow traffic

- [x] Mirror 5% of checkouts to the new relay
- [x] Compare outbox lag against the old poller
- [ ] Alert when lag exceeds 2 seconds

## Phase 2: canary

Route one tenant through the new path for a week. Roll back if the error rate goes above 0.1%.

| Day | Traffic | Owner |
| --- | --- | --- |
| Mon | 1 tenant | Dana |
| Wed | 5 tenants | Dana |
| Fri | 25% | Sam |
| Sat | 50% | Sam |

## Risks

- The old poller and the relay could both publish during the switch.
- Stock reservations may lag behind payment for a few seconds.
- Nobody owns the relay dashboard yet.

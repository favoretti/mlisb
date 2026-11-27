# Notes for coding agents

- Run `make test` before you finish. Contract tests need `make db` running.
- Never write to the `outbox` table outside the transaction that writes the order.
- Update `docs/rollout-plan.md` when a rollout step is done, and say what changed.

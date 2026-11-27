# orders-service

Takes checkouts, reserves stock and charges the ledger. Start with
[Architecture](docs/architecture.md).

## Running it

```sh
make db
make run
```

The API listens on port 8080. `make test` runs the unit and contract tests.

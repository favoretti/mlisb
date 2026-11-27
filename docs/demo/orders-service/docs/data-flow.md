# Data flow

## Checkout, step by step

```d2
direction: right
client -> api: POST /checkout
api -> db: insert order
api -> outbox: order.created
outbox -> bus: publish
bus -> stock: reserve
bus -> ledger: charge
```

## Retry budget

Each worker retries with exponential backoff. The delay before attempt $n$ is

$$
d_n = \min\left(d_{\max},\ d_0 \cdot 2^{n}\right)
$$

With $d_0 = 0.2$ seconds and $d_{\max} = 30$ seconds, a message is given up after about four
minutes.

## Relay query

```sql
SELECT id, topic, payload
FROM outbox
WHERE published_at IS NULL
ORDER BY id
LIMIT 500
FOR UPDATE SKIP LOCKED;
```

The relay marks the rows it published in the same transaction, so two relays never send the same
row.

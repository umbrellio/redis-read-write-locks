# redis-read-write-locks

Distributed read-write locks for Ruby backed by Redis.

- Multiple readers can hold the lock simultaneously
- Writers get exclusive access (blocks all readers and other writers)
- Locks expire automatically via TTL — no deadlock on crash
- Atomic operations via Lua scripts

## Installation

```ruby
gem "redis-read-write-locks"
```

## Usage

```ruby
require "redis"
require "redis_read_write_locks"

client = RedisReadWriteLocks::Client.new(Redis.new(url: "redis://localhost:6379/0"))

# Block form — acquires, yields, releases
client.read_lock("my_resource") { read_data }
client.write_lock("my_resource") { write_data }

# Manual acquire/release
lock = client.read_lock("my_resource")
lock.acquire          # => true / false (non-blocking)
lock.release

# Block on contention — retries for up to N milliseconds
lock.acquire(timeout: 5000)          # raises LockTimeoutError if timeout exceeded
lock.synchronize(timeout: 5000) { }  # acquire + yield + release

# Per-lock TTL override
client.write_lock("my_resource", ttl: 60_000) { long_operation }
```

### Client options

```ruby
client = RedisReadWriteLocks::Client.new(redis, default_ttl: 60_000)
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `ttl`  | `30`    | Lock TTL in seconds. Lock auto-expires if holder crashes. |
| `prefer_writer` | `false` | Write lock only. When `true`, a writer blocked on acquire registers its intent so new readers are refused until it acquires or gives up. Only takes effect when `retry_count` is set — a non-retrying writer isn't waiting, so it registers and immediately clears its intent, making the flag a no-op. |

### Errors

| Error | When |
|-------|------|
| `LockNotAcquiredError` | `synchronize` (no timeout) called when lock is contended |
| `LockTimeoutError` | `acquire(timeout:)` or `synchronize(timeout:)` exceeded timeout |

## Redis key structure

```
rw_lock:writer:<name>           # String, holds owner token, TTL = lock TTL
rw_lock:readers:<name>          # Sorted set, member = token, score = expiry timestamp
rw_lock:pending_writers:<name>  # Sorted set, member = token, score = pending-intent expiry timestamp.
                                 # Populated only by writers using `prefer_writer: true`.
```

## Requirements

- Ruby >= 2.7
- Redis >= 5.0
- `redis` gem >= 4.0

## License

MIT

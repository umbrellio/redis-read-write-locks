# frozen_string_literal: true

module RedisReadWriteLocks
  module LockScripts
    # KEYS[1] = writer_key, KEYS[2] = readers_key, KEYS[3] = pending_writers_key
    # ARGV[1] = token, ARGV[2] = expiry (unix ts), ARGV[3] = now (unix ts), ARGV[4] = ttl (ms)
    # Returns 1 = acquired, 0 = blocked
    ACQUIRE_READ = <<~LUA
      local writer_key = KEYS[1]
      local readers_key = KEYS[2]
      local pending_key = KEYS[3]
      local token = ARGV[1]
      local expiry = tonumber(ARGV[2])
      local now = tonumber(ARGV[3])
      local ttl_ms = tonumber(ARGV[4])

      redis.call('ZREMRANGEBYSCORE', readers_key, '-inf', now)
      redis.call('ZREMRANGEBYSCORE', pending_key, '-inf', now)

      if redis.call('EXISTS', writer_key) == 1 then
        return 0
      end

      if redis.call('ZCARD', pending_key) > 0 then
        return 0
      end

      redis.call('ZADD', readers_key, expiry, token)

      local current_pttl = redis.call('PTTL', readers_key)
      if current_pttl == -1 or current_pttl < ttl_ms then
        redis.call('PEXPIRE', readers_key, ttl_ms)
      end

      return 1
    LUA

    # KEYS[1] = readers_key
    # ARGV[1] = token
    RELEASE_READ = <<~LUA
      redis.call('ZREM', KEYS[1], ARGV[1])
      return 1
    LUA

    # KEYS[1] = writer_key, KEYS[2] = readers_key, KEYS[3] = pending_writers_key
    # ARGV[1] = token, ARGV[2] = ttl (ms), ARGV[3] = now (unix ts),
    # ARGV[4] = prefer (1 = writer preference on), ARGV[5] = pending expiry (unix ts),
    # ARGV[6] = pending ttl (ms)
    # Returns 1 = acquired, 0 = blocked
    ACQUIRE_WRITE = <<~LUA
      local writer_key = KEYS[1]
      local readers_key = KEYS[2]
      local pending_key = KEYS[3]
      local token = ARGV[1]
      local ttl = tonumber(ARGV[2])
      local now = tonumber(ARGV[3])
      local prefer = tonumber(ARGV[4])
      local pending_expiry = tonumber(ARGV[5])
      local pending_ttl_ms = tonumber(ARGV[6])

      redis.call('ZREMRANGEBYSCORE', readers_key, '-inf', now)
      redis.call('ZREMRANGEBYSCORE', pending_key, '-inf', now)

      if redis.call('ZCARD', readers_key) > 0 or redis.call('EXISTS', writer_key) == 1 then
        if prefer == 1 then
          redis.call('ZADD', pending_key, pending_expiry, token)

          local current_pttl = redis.call('PTTL', pending_key)
          if current_pttl == -1 or current_pttl < pending_ttl_ms then
            redis.call('PEXPIRE', pending_key, pending_ttl_ms)
          end
        end

        return 0
      end

      redis.call('SET', writer_key, token, 'PX', ttl)
      redis.call('ZREM', pending_key, token)
      return 1
    LUA

    # KEYS[1] = writer_key
    # ARGV[1] = token
    # Returns 1 = released, 0 = not owner
    RELEASE_WRITE = <<~LUA
      if redis.call('GET', KEYS[1]) == ARGV[1] then
        redis.call('DEL', KEYS[1])
        return 1
      end
      return 0
    LUA

    # KEYS[1] = pending_writers_key
    # ARGV[1] = token
    # Returns 1 = cleared
    CLEAR_PENDING_WRITE = <<~LUA
      redis.call('ZREM', KEYS[1], ARGV[1])
      return 1
    LUA

    # KEYS[1] = writer_key
    # ARGV[1] = token, ARGV[2] = ttl (milliseconds)
    # Returns 1 = refreshed, 0 = not owner
    REFRESH_WRITE = <<~LUA
      if redis.call('GET', KEYS[1]) == ARGV[1] then
        redis.call('PEXPIRE', KEYS[1], ARGV[2])
        return 1
      end
      return 0
    LUA

    # KEYS[1] = readers_key
    # ARGV[1] = token, ARGV[2] = expiry (unix ts), ARGV[3] = now (unix ts), ARGV[4] = ttl (ms)
    # Returns 1 = refreshed, 0 = not in set
    REFRESH_READ = <<~LUA
      local readers_key = KEYS[1]
      local token = ARGV[1]
      local expiry = tonumber(ARGV[2])
      local now = tonumber(ARGV[3])
      local ttl_ms = tonumber(ARGV[4])

      if redis.call('ZSCORE', readers_key, token) == false then
        return 0
      end

      redis.call('ZADD', readers_key, expiry, token)

      local current_pttl = redis.call('PTTL', readers_key)
      if current_pttl == -1 or current_pttl < ttl_ms then
        redis.call('PEXPIRE', readers_key, ttl_ms)
      end

      return 1
    LUA
  end
end

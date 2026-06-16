module RedisReadWriteLocks
  module LockScripts
    # KEYS[1] = writer_key, KEYS[2] = readers_key
    # ARGV[1] = token, ARGV[2] = expiry (unix ts), ARGV[3] = now (unix ts)
    # Returns 1 = acquired, 0 = blocked
    ACQUIRE_READ = <<~LUA.freeze
      local writer_key = KEYS[1]
      local readers_key = KEYS[2]
      local token = ARGV[1]
      local expiry = tonumber(ARGV[2])
      local now = tonumber(ARGV[3])

      redis.call('ZREMRANGEBYSCORE', readers_key, '-inf', now)

      if redis.call('EXISTS', writer_key) == 1 then
        return 0
      end

      redis.call('ZADD', readers_key, expiry, token)

      local current_ttl = redis.call('TTL', readers_key)
      if current_ttl == -1 or (current_ttl > 0 and (now + current_ttl) < expiry) then
        redis.call('EXPIREAT', readers_key, expiry + 1)
      end

      return 1
    LUA

    # KEYS[1] = readers_key
    # ARGV[1] = token
    RELEASE_READ = <<~LUA.freeze
      redis.call('ZREM', KEYS[1], ARGV[1])
      return 1
    LUA

    # KEYS[1] = writer_key, KEYS[2] = readers_key
    # ARGV[1] = token, ARGV[2] = ttl (milliseconds), ARGV[3] = now (unix ts)
    # Returns 1 = acquired, 0 = blocked
    ACQUIRE_WRITE = <<~LUA.freeze
      local writer_key = KEYS[1]
      local readers_key = KEYS[2]
      local token = ARGV[1]
      local ttl = tonumber(ARGV[2])
      local now = tonumber(ARGV[3])

      redis.call('ZREMRANGEBYSCORE', readers_key, '-inf', now)

      if redis.call('ZCARD', readers_key) > 0 then
        return 0
      end

      if redis.call('EXISTS', writer_key) == 1 then
        return 0
      end

      redis.call('SET', writer_key, token, 'PX', ttl)
      return 1
    LUA

    # KEYS[1] = writer_key
    # ARGV[1] = token
    # Returns 1 = released, 0 = not owner
    RELEASE_WRITE = <<~LUA.freeze
      if redis.call('GET', KEYS[1]) == ARGV[1] then
        redis.call('DEL', KEYS[1])
        return 1
      end
      return 0
    LUA

    # KEYS[1] = writer_key
    # ARGV[1] = token, ARGV[2] = ttl (milliseconds)
    # Returns 1 = refreshed, 0 = not owner
    REFRESH_WRITE = <<~LUA.freeze
      if redis.call('GET', KEYS[1]) == ARGV[1] then
        redis.call('PEXPIRE', KEYS[1], ARGV[2])
        return 1
      end
      return 0
    LUA

    # KEYS[1] = readers_key
    # ARGV[1] = token, ARGV[2] = expiry (unix ts), ARGV[3] = now (unix ts)
    # Returns 1 = refreshed, 0 = not in set
    REFRESH_READ = <<~LUA.freeze
      local readers_key = KEYS[1]
      local token = ARGV[1]
      local expiry = tonumber(ARGV[2])
      local now = tonumber(ARGV[3])

      if redis.call('ZSCORE', readers_key, token) == false then
        return 0
      end

      redis.call('ZADD', readers_key, expiry, token)

      local current_ttl = redis.call('TTL', readers_key)
      if current_ttl == -1 or (current_ttl > 0 and (now + current_ttl) < expiry) then
        redis.call('EXPIREAT', readers_key, expiry + 1)
      end

      return 1
    LUA
  end
end

module RedisReadWriteLocks
  class Client
    def initialize(redis, default_ttl: BaseLock::DEFAULT_TTL)
      @redis = redis
      @default_ttl = default_ttl
    end

    def read_lock(name, ttl: @default_ttl, timeout: nil, &block)
      lock = ReadLock.new(redis: @redis, name: name, ttl: ttl)
      block ? lock.synchronize(timeout: timeout, &block) : lock
    end

    def write_lock(name, ttl: @default_ttl, timeout: nil, &block)
      lock = WriteLock.new(redis: @redis, name: name, ttl: ttl)
      block ? lock.synchronize(timeout: timeout, &block) : lock
    end
  end
end

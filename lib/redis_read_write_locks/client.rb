module RedisReadWriteLocks
  class Client
    def initialize(redis, default_ttl: BaseLock::DEFAULT_TTL)
      @redis = redis
      @default_ttl = default_ttl
    end

    def read_lock(name, ttl: @default_ttl, retry_count: nil, retry_delay: BaseLock::DEFAULT_RETRY_DELAY, &block)
      lock = ReadLock.new(redis: @redis, name: name, ttl: ttl)
      block ? lock.synchronize(retry_count: retry_count, retry_delay: retry_delay, &block) : lock
    end

    def write_lock(name, ttl: @default_ttl, retry_count: nil, retry_delay: BaseLock::DEFAULT_RETRY_DELAY, &block)
      lock = WriteLock.new(redis: @redis, name: name, ttl: ttl)
      block ? lock.synchronize(retry_count: retry_count, retry_delay: retry_delay, &block) : lock
    end
  end
end

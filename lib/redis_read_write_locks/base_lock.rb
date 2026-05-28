require "securerandom"

module RedisReadWriteLocks
  class BaseLock
    DEFAULT_TTL = 30_000
    DEFAULT_RETRY_DELAY = 100

    attr_reader :name, :token

    def initialize(redis:, name:, ttl: DEFAULT_TTL)
      @redis = redis
      @name = name
      @ttl = ttl
      @token = SecureRandom.uuid
      @acquired = false
    end

    def acquired?
      @acquired
    end

    def acquire(retry_count: nil, retry_delay: DEFAULT_RETRY_DELAY)
      return try_acquire if retry_count.nil?

      return true if try_acquire
      retry_count.times do
        sleep retry_delay / 1000.0
        return true if try_acquire
      end
      raise LockTimeoutError, "Could not acquire #{lock_type} lock '#{@name}' after #{retry_count} retries"
    end

    def synchronize(retry_count: nil, retry_delay: DEFAULT_RETRY_DELAY, &block)
      if retry_count
        acquire(retry_count: retry_count, retry_delay: retry_delay)
      else
        acquire || raise(LockNotAcquiredError, "Could not acquire #{lock_type} lock '#{@name}'")
      end
      begin
        block.call
      ensure
        release
      end
    end

    private

    def writer_key
      "rw_lock:writer:#{@name}"
    end

    def readers_key
      "rw_lock:readers:#{@name}"
    end

    def lock_type
      self.class.name.split("::").last.sub("Lock", "").downcase
    end

    def eval_script(script, keys:, argv:)
      if @redis.respond_to?(:eval)
        @redis.eval(script, keys: keys, argv: argv)
      else
        @redis.call("EVAL", script, keys.length, *keys, *argv)
      end
    end
  end
end

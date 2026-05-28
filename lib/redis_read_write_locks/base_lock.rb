require "securerandom"

module RedisReadWriteLocks
  class BaseLock
    DEFAULT_TTL = 30
    RETRY_INTERVAL = 0.01

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

    # Non-blocking: returns true/false.
    # With timeout: retries for timeout seconds, returns true or raises LockTimeoutError.
    def acquire(timeout: nil)
      return try_acquire if timeout.nil?

      deadline = Time.now.to_f + timeout
      loop do
        return true if try_acquire
        raise LockTimeoutError, "Timeout acquiring #{lock_type} lock '#{@name}'" if Time.now.to_f >= deadline
        sleep RETRY_INTERVAL
      end
    end

    # Acquires lock, yields, releases. Raises LockNotAcquiredError if non-blocking acquire fails.
    def synchronize(timeout: nil, &block)
      if timeout
        acquire(timeout: timeout)
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

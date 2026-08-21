# frozen_string_literal: true

require "securerandom"

module RedisReadWriteLocks
  class BaseLock
    DEFAULT_TTL = 30_000
    DEFAULT_RETRY_DELAY = 100
    PENDING_WRITER_TTL = 30_000

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
      @retry_delay = retry_count.nil? ? 0 : retry_delay

      return try_acquire if retry_count.nil?

      return true if try_acquire

      retry_count.times do
        sleep retry_delay / 1000.0
        return true if try_acquire
      end
      raise LockTimeoutError, "Could not acquire #{lock_type} lock '#{@name}' after #{retry_count} retries"
    ensure
      begin
        abandon_pending unless acquired?
      rescue StandardError
        nil
      end
    end

    WATCHDOG_REFRESH_INTERVAL = 10
    WATCHDOG_SLEEP_INTERVAL = 0.5

    def synchronize(retry_count: nil, retry_delay: DEFAULT_RETRY_DELAY, &block)
      acquire_or_raise(retry_count: retry_count, retry_delay: retry_delay)
      stop = Thread::Queue.new
      watchdog = start_watchdog(Thread.current, stop)
      begin
        block.call
      ensure
        stop.close
        watchdog.join
        release
      end
    end

    private

    def acquire_or_raise(retry_count:, retry_delay:)
      return acquire(retry_count: retry_count, retry_delay: retry_delay) if retry_count

      acquire || raise(LockNotAcquiredError, "Could not acquire #{lock_type} lock '#{@name}'")
    end

    # Waits on the queue rather than sleeping, so closing it on release wakes the
    # watchdog at once. While it slept, every synchronize paid up to a full
    # WATCHDOG_SLEEP_INTERVAL on the way out - far more than a short critical
    # section takes, and callers that take many brief locks paid it every time.
    def start_watchdog(main_thread, stop)
      Thread.new do
        elapsed = 0.0
        loop do
          stop.pop(timeout: WATCHDOG_SLEEP_INTERVAL)
          break if stop.closed?

          elapsed += WATCHDOG_SLEEP_INTERVAL
          next unless elapsed >= WATCHDOG_REFRESH_INTERVAL

          elapsed = 0.0
          begin
            unless refresh
              main_thread.raise(LockRefreshError, "Could not refresh #{lock_type} lock '#{@name}'")
              break
            end
          rescue StandardError => e
            main_thread.raise(e)
            break
          end
        end
      end
    end

    def writer_key
      "rw_lock:writer:#{@name}"
    end

    def readers_key
      "rw_lock:readers:#{@name}"
    end

    def pending_writers_key
      "rw_lock:pending_writers:#{@name}"
    end

    def abandon_pending
      nil
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

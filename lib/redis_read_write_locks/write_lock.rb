# frozen_string_literal: true

module RedisReadWriteLocks
  class WriteLock < BaseLock
    def initialize(redis:, name:, ttl: DEFAULT_TTL, prefer_writer: false)
      super(redis: redis, name: name, ttl: ttl)
      @prefer_writer = prefer_writer
    end

    def release
      return false unless @acquired

      eval_script(LockScripts::RELEASE_WRITE, keys: [writer_key], argv: [@token])
      @acquired = false
      true
    end

    def refresh
      return false unless @acquired

      eval_script(LockScripts::REFRESH_WRITE, keys: [writer_key], argv: [@token, @ttl]) == 1
    end

    private

    def try_acquire
      now = Time.now.to_i
      pending_expiry = now + (PENDING_WRITER_TTL / 1000.0).ceil

      result = eval_script(
        LockScripts::ACQUIRE_WRITE,
        keys: [writer_key, readers_key, pending_writers_key],
        argv: [
          @token, @ttl, now, @prefer_writer ? 1 : 0, pending_expiry, PENDING_WRITER_TTL
        ]
      )

      @acquired = result == 1
    end

    def abandon_pending
      return unless @prefer_writer

      eval_script(LockScripts::CLEAR_PENDING_WRITE, keys: [pending_writers_key], argv: [@token])
    end
  end
end

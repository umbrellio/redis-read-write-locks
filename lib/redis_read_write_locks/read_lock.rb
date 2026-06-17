# frozen_string_literal: true

module RedisReadWriteLocks
  class ReadLock < BaseLock
    def release
      return false unless @acquired

      eval_script(LockScripts::RELEASE_READ, keys: [readers_key], argv: [@token])
      @acquired = false
      true
    end

    def refresh
      return false unless @acquired

      now = Time.now.to_i
      expiry = now + (@ttl / 1000.0).ceil
      eval_script(LockScripts::REFRESH_READ, keys: [readers_key], argv: [@token, expiry, now, @ttl]) == 1
    end

    private

    def try_acquire
      now = Time.now.to_i
      expiry = now + (@ttl / 1000.0).ceil

      result = eval_script(
        LockScripts::ACQUIRE_READ,
        keys: [writer_key, readers_key],
        argv: [@token, expiry, now, @ttl]
      )

      @acquired = result == 1
    end
  end
end

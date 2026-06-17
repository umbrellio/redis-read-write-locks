# frozen_string_literal: true

module RedisReadWriteLocks
  class WriteLock < BaseLock
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
      result = eval_script(
        LockScripts::ACQUIRE_WRITE,
        keys: [writer_key, readers_key],
        argv: [@token, @ttl, Time.now.to_i]
      )

      @acquired = result == 1
    end
  end
end

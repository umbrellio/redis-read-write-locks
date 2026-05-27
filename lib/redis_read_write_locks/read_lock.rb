module RedisReadWriteLocks
  class ReadLock < BaseLock
    def release
      return false unless @acquired

      eval_script(LockScripts::RELEASE_READ, keys: [readers_key], argv: [@token])
      @acquired = false
      true
    end

    private

    def try_acquire
      now = Time.now.to_i
      expiry = now + @ttl

      result = eval_script(
        LockScripts::ACQUIRE_READ,
        keys: [writer_key, readers_key],
        argv: [@token, expiry, now],
      )

      @acquired = result == 1
    end
  end
end

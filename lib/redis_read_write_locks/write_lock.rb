module RedisReadWriteLocks
  class WriteLock < BaseLock
    def release
      return false unless @acquired

      eval_script(LockScripts::RELEASE_WRITE, keys: [writer_key], argv: [@token])
      @acquired = false
      true
    end

    private

    def try_acquire
      result = eval_script(
        LockScripts::ACQUIRE_WRITE,
        keys: [writer_key, readers_key],
        argv: [@token, @ttl / 1000, Time.now.to_i],
      )

      @acquired = result == 1
    end
  end
end

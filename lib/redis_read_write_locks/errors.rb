module RedisReadWriteLocks
  Error = Class.new(StandardError)
  LockNotAcquiredError = Class.new(Error)
  LockTimeoutError = Class.new(Error)
end

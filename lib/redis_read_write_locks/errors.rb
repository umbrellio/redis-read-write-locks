# frozen_string_literal: true

module RedisReadWriteLocks
  class Error < StandardError
  end

  class LockNotAcquiredError < Error
  end

  class LockTimeoutError < Error
  end

  class LockRefreshError < Error
  end
end

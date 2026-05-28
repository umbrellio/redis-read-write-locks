RSpec.describe RedisReadWriteLocks::Client do
  subject(:client) { described_class.new(REDIS) }

  describe "#read_lock" do
    it "returns ReadLock when no block given" do
      lock = client.read_lock("res")
      expect(lock).to be_a(RedisReadWriteLocks::ReadLock)
    end

    it "acquires and releases when block given" do
      acquired = nil
      client.read_lock("res") { acquired = true }
      expect(acquired).to be true
    end

    it "passes ttl to lock" do
      lock = client.read_lock("res", ttl: 99_000)
      expect(lock.instance_variable_get(:@ttl)).to eq(99_000)
    end

    it "retries until writer releases when retry_count given" do
      writer = RedisReadWriteLocks::WriteLock.new(redis: REDIS, name: "res", ttl: 10_000)
      writer.acquire
      Thread.new { sleep 0.05; writer.release }

      acquired = nil
      client.read_lock("res", retry_count: 20, retry_delay: 10) { acquired = true }
      expect(acquired).to be true
    end

    it "raises LockTimeoutError when contended and retries exhausted" do
      writer = RedisReadWriteLocks::WriteLock.new(redis: REDIS, name: "res", ttl: 10_000)
      writer.acquire

      expect { client.read_lock("res", retry_count: 2, retry_delay: 10) {} }.to raise_error(RedisReadWriteLocks::LockTimeoutError)
      writer.release
    end

    it "raises LockNotAcquiredError when contended and no timeout given" do
      writer = RedisReadWriteLocks::WriteLock.new(redis: REDIS, name: "res", ttl: 10_000)
      writer.acquire

      expect { client.read_lock("res") {} }.to raise_error(RedisReadWriteLocks::LockNotAcquiredError)
      writer.release
    end
  end

  describe "#write_lock" do
    it "returns WriteLock when no block given" do
      lock = client.write_lock("res")
      expect(lock).to be_a(RedisReadWriteLocks::WriteLock)
    end

    it "acquires and releases when block given" do
      acquired = nil
      client.write_lock("res") { acquired = true }
      expect(acquired).to be true
    end

    it "retries until reader releases when retry_count given" do
      reader = RedisReadWriteLocks::ReadLock.new(redis: REDIS, name: "res", ttl: 10_000)
      reader.acquire
      Thread.new { sleep 0.05; reader.release }

      acquired = nil
      client.write_lock("res", retry_count: 20, retry_delay: 10) { acquired = true }
      expect(acquired).to be true
    end

    it "raises LockTimeoutError when contended and retries exhausted" do
      reader = RedisReadWriteLocks::ReadLock.new(redis: REDIS, name: "res", ttl: 10_000)
      reader.acquire

      expect { client.write_lock("res", retry_count: 2, retry_delay: 10) {} }.to raise_error(RedisReadWriteLocks::LockTimeoutError)
      reader.release
    end

    it "raises LockNotAcquiredError when contended and no timeout given" do
      reader = RedisReadWriteLocks::ReadLock.new(redis: REDIS, name: "res", ttl: 10_000)
      reader.acquire

      expect { client.write_lock("res") {} }.to raise_error(RedisReadWriteLocks::LockNotAcquiredError)
      reader.release
    end
  end

  describe "default_ttl" do
    it "applies to all locks" do
      client = described_class.new(REDIS, default_ttl: 42_000)
      lock = client.read_lock("res")
      expect(lock.instance_variable_get(:@ttl)).to eq(42_000)
    end
  end

  it "multiple read locks coexist" do
    r1 = client.read_lock("res")
    r2 = client.read_lock("res")
    expect(r1.acquire).to be true
    expect(r2.acquire).to be true
    r1.release
    r2.release
  end

  it "write lock blocks read lock" do
    w = client.write_lock("res")
    r = client.read_lock("res")
    w.acquire
    expect(r.acquire).to be false
    w.release
  end
end

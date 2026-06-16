RSpec.describe RedisReadWriteLocks::ReadLock do
  subject(:lock) { described_class.new(redis: REDIS, name: "test_resource", ttl: 10_000) }

  describe "#acquire" do
    it "acquires when no locks held" do
      expect(lock.acquire).to be true
      expect(lock.acquired?).to be true
    end

    it "acquires when another reader holds lock" do
      other = described_class.new(redis: REDIS, name: "test_resource", ttl: 10_000)
      other.acquire

      expect(lock.acquire).to be true
    end

    it "fails when writer holds lock" do
      writer = RedisReadWriteLocks::WriteLock.new(redis: REDIS, name: "test_resource", ttl: 10_000)
      writer.acquire

      expect(lock.acquire).to be false
      expect(lock.acquired?).to be false
    end

    it "blocks different resource names independently" do
      writer = RedisReadWriteLocks::WriteLock.new(redis: REDIS, name: "other_resource", ttl: 10_000)
      writer.acquire

      expect(lock.acquire).to be true
    end

    context "with retry_count" do
      it "retries and acquires when writer releases" do
        writer = RedisReadWriteLocks::WriteLock.new(redis: REDIS, name: "test_resource", ttl: 10_000)
        writer.acquire

        Thread.new { sleep 0.05; writer.release }

        expect(lock.acquire(retry_count: 20, retry_delay: 10)).to be true
      end

      it "raises LockTimeoutError when retries exhausted" do
        writer = RedisReadWriteLocks::WriteLock.new(redis: REDIS, name: "test_resource", ttl: 10_000)
        writer.acquire

        expect { lock.acquire(retry_count: 2, retry_delay: 10) }.to raise_error(RedisReadWriteLocks::LockTimeoutError)
      end
    end
  end

  describe "#release" do
    it "releases held lock" do
      lock.acquire
      expect(lock.release).to be true
      expect(lock.acquired?).to be false
    end

    it "returns false when not acquired" do
      expect(lock.release).to be false
    end

    it "allows writer to acquire after release" do
      lock.acquire
      lock.release

      writer = RedisReadWriteLocks::WriteLock.new(redis: REDIS, name: "test_resource", ttl: 10_000)
      expect(writer.acquire).to be true
    end
  end

  describe "#refresh" do
    it "returns false when not acquired" do
      expect(lock.refresh).to be false
    end

    it "extends TTL of held lock" do
      short_lock = described_class.new(redis: REDIS, name: "test_resource", ttl: 500)
      short_lock.acquire
      sleep 0.4
      expect(short_lock.refresh).to be true
      sleep 0.4
      expect(REDIS.exists?("rw_lock:readers:test_resource")).to be true
      short_lock.release
    end
  end

  describe "#synchronize" do
    it "acquires, yields, releases" do
      result = nil
      lock.synchronize { result = lock.acquired? }

      expect(result).to be true
      expect(lock.acquired?).to be false
    end

    it "releases even when block raises" do
      expect { lock.synchronize { raise "oops" } }.to raise_error("oops")
      expect(lock.acquired?).to be false
    end

    it "raises LockNotAcquiredError when blocked" do
      writer = RedisReadWriteLocks::WriteLock.new(redis: REDIS, name: "test_resource", ttl: 10_000)
      writer.acquire

      expect { lock.synchronize {} }.to raise_error(RedisReadWriteLocks::LockNotAcquiredError)
    end

    it "waits for lock with retry_count" do
      writer = RedisReadWriteLocks::WriteLock.new(redis: REDIS, name: "test_resource", ttl: 10_000)
      writer.acquire
      Thread.new { sleep 0.05; writer.release }

      expect { lock.synchronize(retry_count: 20, retry_delay: 10) {} }.not_to raise_error
    end

    it "watchdog keeps lock alive beyond TTL" do
      short_lock = described_class.new(redis: REDIS, name: "test_resource", ttl: 500)
      short_lock.synchronize do
        sleep 0.8
        expect(REDIS.exists?("rw_lock:readers:test_resource")).to be true
      end
    end
  end
end

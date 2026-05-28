RSpec.describe RedisReadWriteLocks::WriteLock do
  subject(:lock) { described_class.new(redis: REDIS, name: "test_resource", ttl: 10_000) }

  describe "#acquire" do
    it "acquires when no locks held" do
      expect(lock.acquire).to be true
      expect(lock.acquired?).to be true
    end

    it "fails when reader holds lock" do
      reader = RedisReadWriteLocks::ReadLock.new(redis: REDIS, name: "test_resource", ttl: 10_000)
      reader.acquire

      expect(lock.acquire).to be false
    end

    it "fails when another writer holds lock" do
      other = described_class.new(redis: REDIS, name: "test_resource", ttl: 10_000)
      other.acquire

      expect(lock.acquire).to be false
    end

    it "blocks different resource names independently" do
      other_lock = described_class.new(redis: REDIS, name: "other_resource", ttl: 10_000)
      other_lock.acquire

      expect(lock.acquire).to be true
    end

    context "with retry_count" do
      it "retries and acquires when reader releases" do
        reader = RedisReadWriteLocks::ReadLock.new(redis: REDIS, name: "test_resource", ttl: 10_000)
        reader.acquire

        Thread.new { sleep 0.05; reader.release }

        expect(lock.acquire(retry_count: 20, retry_delay: 10)).to be true
      end

      it "raises LockTimeoutError when retries exhausted" do
        reader = RedisReadWriteLocks::ReadLock.new(redis: REDIS, name: "test_resource", ttl: 10_000)
        reader.acquire

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

    it "does not release lock owned by different token" do
      lock.acquire

      imposter = described_class.new(redis: REDIS, name: "test_resource", ttl: 10_000)
      imposter.instance_variable_set(:@acquired, true)
      imposter.release

      expect(lock.acquired?).to be true
      expect(REDIS.exists?("rw_lock:writer:test_resource")).to be true
    end

    it "allows readers after release" do
      lock.acquire
      lock.release

      reader = RedisReadWriteLocks::ReadLock.new(redis: REDIS, name: "test_resource", ttl: 10_000)
      expect(reader.acquire).to be true
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
      other = described_class.new(redis: REDIS, name: "test_resource", ttl: 10_000)
      other.acquire

      expect { lock.synchronize {} }.to raise_error(RedisReadWriteLocks::LockNotAcquiredError)
    end
  end
end

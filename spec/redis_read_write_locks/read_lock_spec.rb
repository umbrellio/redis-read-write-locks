RSpec.describe RedisReadWriteLocks::ReadLock do
  subject(:lock) { described_class.new(redis: REDIS, name: "test_resource", ttl: 10) }

  describe "#acquire" do
    it "acquires when no locks held" do
      expect(lock.acquire).to be true
      expect(lock.acquired?).to be true
    end

    it "acquires when another reader holds lock" do
      other = described_class.new(redis: REDIS, name: "test_resource", ttl: 10)
      other.acquire

      expect(lock.acquire).to be true
    end

    it "fails when writer holds lock" do
      writer = RedisReadWriteLocks::WriteLock.new(redis: REDIS, name: "test_resource", ttl: 10)
      writer.acquire

      expect(lock.acquire).to be false
      expect(lock.acquired?).to be false
    end

    it "blocks different resource names independently" do
      writer = RedisReadWriteLocks::WriteLock.new(redis: REDIS, name: "other_resource", ttl: 10)
      writer.acquire

      expect(lock.acquire).to be true
    end

    context "with timeout" do
      it "retries and acquires when writer releases" do
        writer = RedisReadWriteLocks::WriteLock.new(redis: REDIS, name: "test_resource", ttl: 10)
        writer.acquire

        Thread.new { sleep 0.05; writer.release }

        expect(lock.acquire(timeout: 1000)).to be true
      end

      it "raises LockTimeoutError when timeout exceeded" do
        writer = RedisReadWriteLocks::WriteLock.new(redis: REDIS, name: "test_resource", ttl: 10)
        writer.acquire

        expect { lock.acquire(timeout: 50) }.to raise_error(RedisReadWriteLocks::LockTimeoutError)
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

      writer = RedisReadWriteLocks::WriteLock.new(redis: REDIS, name: "test_resource", ttl: 10)
      expect(writer.acquire).to be true
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
      writer = RedisReadWriteLocks::WriteLock.new(redis: REDIS, name: "test_resource", ttl: 10)
      writer.acquire

      expect { lock.synchronize {} }.to raise_error(RedisReadWriteLocks::LockNotAcquiredError)
    end

    it "waits for lock with timeout" do
      writer = RedisReadWriteLocks::WriteLock.new(redis: REDIS, name: "test_resource", ttl: 10)
      writer.acquire
      Thread.new { sleep 0.05; writer.release }

      expect { lock.synchronize(timeout: 1000) {} }.not_to raise_error
    end
  end
end

# frozen_string_literal: true

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

        Thread.new do
          sleep 0.05
          reader.release
        end

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
      expect(REDIS.exists?("rw_lock:writer:test_resource")).to be true
      short_lock.release
    end

    it "returns false when lock expired in Redis" do
      lock.acquire
      REDIS.del("rw_lock:writer:test_resource")
      expect(lock.refresh).to be false
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

    it "watchdog keeps lock alive beyond TTL" do
      stub_const("RedisReadWriteLocks::BaseLock::WATCHDOG_REFRESH_INTERVAL", 0.1)
      stub_const("RedisReadWriteLocks::BaseLock::WATCHDOG_SLEEP_INTERVAL", 0.05)

      short_lock = described_class.new(redis: REDIS, name: "test_resource", ttl: 500)
      short_lock.synchronize do
        sleep 0.8
        expect(REDIS.exists?("rw_lock:writer:test_resource")).to be true
      end
    end

    it "raises LockRefreshError in main thread when lock lost in Redis" do
      stub_const("RedisReadWriteLocks::BaseLock::WATCHDOG_REFRESH_INTERVAL", 0.1)
      stub_const("RedisReadWriteLocks::BaseLock::WATCHDOG_SLEEP_INTERVAL", 0.05)

      short_lock = described_class.new(redis: REDIS, name: "test_resource", ttl: 10_000)
      expect do
        short_lock.synchronize do
          REDIS.del("rw_lock:writer:test_resource")
          sleep 0.5
        end
      end.to raise_error(RedisReadWriteLocks::LockRefreshError)
    end

    it "raises exception from refresh in main thread" do
      stub_const("RedisReadWriteLocks::BaseLock::WATCHDOG_REFRESH_INTERVAL", 0.1)
      stub_const("RedisReadWriteLocks::BaseLock::WATCHDOG_SLEEP_INTERVAL", 0.05)

      allow(lock).to receive(:refresh).and_raise(Redis::CommandError, "READONLY")
      expect do
        lock.synchronize { sleep 0.5 }
      end.to raise_error(Redis::CommandError, "READONLY")
    end
  end

  describe "writer preference" do
    def read_lock
      RedisReadWriteLocks::ReadLock.new(redis: REDIS, name: "test_resource", ttl: 10_000)
    end

    def preferring_writer
      described_class.new(
        redis: REDIS, name: "test_resource", ttl: 10_000, prefer_writer: true
      )
    end

    it "blocks a new reader while a preferring writer waits" do
      holder = read_lock
      holder.acquire

      writer = preferring_writer
      waiting = Thread.new { writer.acquire(retry_count: 300, retry_delay: 10) }
      sleep 0.2

      expect(read_lock.acquire).to be false

      holder.release
      expect(waiting.value).to be true
      expect(REDIS.zcard("rw_lock:pending_writers:test_resource")).to eq(0)
    end

    it "does not block new readers when prefer_writer is false" do
      holder = read_lock
      holder.acquire

      writer = described_class.new(redis: REDIS, name: "test_resource", ttl: 10_000)
      expect(writer.acquire).to be false

      expect(read_lock.acquire).to be true
    end

    it "lets a reader that already holds the lock keep refreshing" do
      holder = read_lock
      holder.acquire

      writer = preferring_writer
      waiting = Thread.new { writer.acquire(retry_count: 300, retry_delay: 10) }
      sleep 0.2

      expect(holder.refresh).to be true
      expect(read_lock.acquire).to be false

      holder.release
      expect(waiting.value).to be true
    end

    it "stops blocking readers once an unrefreshed pending entry expires" do
      pending_key = "rw_lock:pending_writers:test_resource"

      # A live writer would keep this score in the future.
      REDIS.zadd(pending_key, Time.now.to_i + 5, "dead-writer-token")
      expect(read_lock.acquire).to be false

      # The writer is killed: nothing refreshes the score, so it falls behind now.
      REDIS.zadd(pending_key, Time.now.to_i - 1, "dead-writer-token")
      expect(read_lock.acquire).to be true
    end

    it "clears its pending entry when retries are exhausted" do
      holder = read_lock
      holder.acquire

      writer = preferring_writer

      expect { writer.acquire(retry_count: 2, retry_delay: 10) }
        .to raise_error(RedisReadWriteLocks::LockTimeoutError)

      expect(REDIS.zcard("rw_lock:pending_writers:test_resource")).to eq(0)
      expect(read_lock.acquire).to be true
    end

    it "sizes the pending TTL from retry_delay so intent survives the gap until the next retry" do
      holder = read_lock
      holder.acquire

      writer = preferring_writer
      writer.instance_variable_set(:@retry_delay, 60_000)
      writer.send(:try_acquire)

      expect(REDIS.pttl("rw_lock:pending_writers:test_resource")).to be > 30_000
    end

    it "keeps the default 30s pending TTL floor when retry_delay is small" do
      holder = read_lock
      holder.acquire

      writer = preferring_writer
      writer.instance_variable_set(:@retry_delay, 10)
      writer.send(:try_acquire)

      expect(REDIS.pttl("rw_lock:pending_writers:test_resource")).to be <= 30_000
    end

    it "raises LockTimeoutError even when abandon_pending fails during cleanup" do
      holder = read_lock
      holder.acquire

      writer = preferring_writer
      allow(writer).to receive(:abandon_pending).and_raise(Redis::CommandError, "READONLY")

      expect { writer.acquire(retry_count: 2, retry_delay: 10) }
        .to raise_error(RedisReadWriteLocks::LockTimeoutError)
    end

    it "keeps readers blocked while another writer is still pending" do
      holder = read_lock
      holder.acquire

      writer_b = preferring_writer
      waiting_b = Thread.new { writer_b.acquire(retry_count: 300, retry_delay: 10) }
      sleep 0.2

      writer_a = preferring_writer
      expect { writer_a.acquire(retry_count: 1, retry_delay: 10) }
        .to raise_error(RedisReadWriteLocks::LockTimeoutError)

      # Only writer_a's intent is gone; writer_b is still waiting.
      expect(REDIS.zcard("rw_lock:pending_writers:test_resource")).to eq(1)
      expect(read_lock.acquire).to be false

      holder.release
      expect(waiting_b.value).to be true
    end
  end
end

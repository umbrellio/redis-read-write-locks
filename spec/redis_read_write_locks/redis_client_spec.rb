# frozen_string_literal: true

require "redis-client"

RSpec.describe "redis-client compatibility" do
  let(:url) { ENV.fetch("REDIS_URL", "redis://localhost:6379/15") }

  shared_examples "read-write lock behavior" do |_client_desc|
    let(:name) { "rc_resource" }

    before { redis.call("FLUSHDB") }

    it "read lock acquires and releases" do
      lock = RedisReadWriteLocks::ReadLock.new(redis: redis, name: name, ttl: 10_000)
      expect(lock.acquire).to be true
      expect(lock.release).to be true
    end

    it "write lock acquires and releases" do
      lock = RedisReadWriteLocks::WriteLock.new(redis: redis, name: name, ttl: 10_000)
      expect(lock.acquire).to be true
      expect(lock.release).to be true
    end

    it "writer blocks reader" do
      writer = RedisReadWriteLocks::WriteLock.new(redis: redis, name: name, ttl: 10_000)
      reader = RedisReadWriteLocks::ReadLock.new(redis: redis, name: name, ttl: 10_000)
      writer.acquire
      expect(reader.acquire).to be false
      writer.release
    end

    it "multiple readers coexist" do
      r1 = RedisReadWriteLocks::ReadLock.new(redis: redis, name: name, ttl: 10_000)
      r2 = RedisReadWriteLocks::ReadLock.new(redis: redis, name: name, ttl: 10_000)
      expect(r1.acquire).to be true
      expect(r2.acquire).to be true
      r1.release
      r2.release
    end

    it "synchronize acquires, yields, releases" do
      lock = RedisReadWriteLocks::WriteLock.new(redis: redis, name: name, ttl: 10_000)
      yielded = false
      lock.synchronize { yielded = true }
      expect(yielded).to be true
      expect(lock.acquired?).to be false
    end
  end

  context "with RedisClient" do
    let(:redis) { RedisClient.new(url: url) }

    after { redis.close }

    include_examples "read-write lock behavior", "RedisClient"
  end

  context "with RedisClient::Pooled" do
    let(:redis) { RedisClient.config(url: url).new_pool(size: 3) }

    after { redis.close }

    include_examples "read-write lock behavior", "RedisClient::Pooled"
  end
end

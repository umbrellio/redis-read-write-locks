RSpec.describe "concurrent read-write locking" do
  let(:name) { "shared_resource" }
  let(:redis) { REDIS }

  it "allows many concurrent readers" do
    readers = 5.times.map { RedisReadWriteLocks::ReadLock.new(redis: redis, name: name, ttl: 5) }
    results = readers.map { |r| r.acquire }

    expect(results).to all(be true)

    readers.each(&:release)
  end

  it "writer waits for all readers to finish" do
    reader = RedisReadWriteLocks::ReadLock.new(redis: redis, name: name, ttl: 5)
    writer = RedisReadWriteLocks::WriteLock.new(redis: redis, name: name, ttl: 5)

    reader.acquire

    acquired_at = nil
    reader_released_at = nil

    writer_thread = Thread.new do
      writer.acquire(timeout: 2)
      acquired_at = Time.now.to_f
    end

    sleep 0.1
    reader_released_at = Time.now.to_f
    reader.release

    writer_thread.join

    expect(acquired_at).to be >= reader_released_at
    writer.release
  end

  it "readers wait for writer to finish" do
    writer = RedisReadWriteLocks::WriteLock.new(redis: redis, name: name, ttl: 5)
    reader = RedisReadWriteLocks::ReadLock.new(redis: redis, name: name, ttl: 5)

    writer.acquire

    acquired_at = nil
    writer_released_at = nil

    reader_thread = Thread.new do
      reader.acquire(timeout: 2)
      acquired_at = Time.now.to_f
    end

    sleep 0.1
    writer_released_at = Time.now.to_f
    writer.release

    reader_thread.join

    expect(acquired_at).to be >= writer_released_at
    reader.release
  end

  it "client helpers work" do
    client = RedisReadWriteLocks::Client.new(redis)
    result = nil
    client.read_lock(name) { result = "read" }
    expect(result).to eq("read")

    client.write_lock(name) { result = "write" }
    expect(result).to eq("write")
  end

  it "lock expires automatically after TTL" do
    writer = RedisReadWriteLocks::WriteLock.new(redis: redis, name: name, ttl: 1)
    writer.acquire

    reader = RedisReadWriteLocks::ReadLock.new(redis: redis, name: name, ttl: 5)
    expect(reader.acquire).to be false

    sleep 1.1

    expect(reader.acquire).to be true
    reader.release
  end
end

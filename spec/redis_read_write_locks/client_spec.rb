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
      lock = client.read_lock("res", ttl: 99)
      expect(lock.instance_variable_get(:@ttl)).to eq(99)
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
  end

  describe "default_ttl" do
    it "applies to all locks" do
      client = described_class.new(REDIS, default_ttl: 42)
      lock = client.read_lock("res")
      expect(lock.instance_variable_get(:@ttl)).to eq(42)
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

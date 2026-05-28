require_relative "lib/redis_read_write_locks/version"

Gem::Specification.new do |spec|
  spec.name = "redis-read-write-locks"
  spec.version = RedisReadWriteLocks::VERSION
  spec.authors = ["Umbrellio"]
  spec.email = ["oss@umbrellio.biz"]
  spec.summary = "Distributed read-write locks using Redis"
  spec.description = "Redis-backed distributed read-write locks. Multiple concurrent readers, exclusive writers."
  spec.homepage = "https://github.com/umbrellio/redis-read-write-locks"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir["lib/**/*.rb", "*.gemspec", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "redis", ">= 4.0"
  spec.add_development_dependency "redis-client"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rake", "~> 13.0"
end

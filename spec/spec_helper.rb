# frozen_string_literal: true

require "redis"
require "redis_read_write_locks"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.order = :random

  REDIS = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/15"))

  config.before do
    REDIS.flushdb
  end
end

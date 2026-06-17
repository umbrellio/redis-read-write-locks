# frozen_string_literal: true

require "rake/testtask"
require "bundler/gem_tasks"

begin
  require "rspec/core/rake_task"
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
  # rspec not available
end

task default: :spec

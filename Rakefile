require "rake/testtask"

# Discover each gemspec subdirectory and delegate test runs.
SUBGEMS = Dir.glob("*/").map { |d| d.chomp("/") }.select do |d|
  File.exist?(File.join(d, "#{d}.gemspec"))
end

namespace :test do
  SUBGEMS.each do |gem_name|
    desc "Run tests for #{gem_name}"
    task gem_name do
      Dir.chdir(gem_name) do
        sh "bundle exec rake test"
      end
    end
  end
end

desc "Run tests for all gems in the monorepo"
task test: SUBGEMS.map { |g| "test:#{g}" }

task default: :test

require "rake"
require "rubocop/rake_task"
require "rspec/core/rake_task"

RuboCop::RakeTask.new
RSpec::Core::RakeTask.new

desc "Lint Ruby"
task :lint do
  sh "bundle exec rubocop --format clang"
end

task default: %i[rubocop spec lint]

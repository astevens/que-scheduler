require 'bundler/setup'

require 'coveralls'
Coveralls.wear!

# By default, que-scheduler specs run in different timezones with every execution, thanks to
# zonebie. If you want to force one particular timezone, you can use the following:
# ENV['ZONEBIE_TZ'] = 'International Date Line West'
# Require zonebie before any other gem to ensure it sets the correct test timezone.
# Setting zonebie to London for travis tests so it matches the .travis.yml ENV.
ENV['ZONEBIE_TZ'] = 'Europe/London' if ENV['TRAVIS'] == 'true'
require 'zonebie/rspec'

Bundler.require :default, :development

Dir["#{__dir__}/../spec/support/**/*.rb"].each { |f| require f }

Que::Scheduler.configure do |config|
  config.schedule_location = "#{__dir__}/config/que_schedule.yml"
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!
  config.full_backtrace = true
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  config.before(:each) do
    ::Que.clear!
    expect(Que.execute('select * from que_scheduler_audit').count).to eq(0)
    expect(Que.execute('select * from que_scheduler_audit_enqueued').count).to eq(0)
  end
  config.before(:suite) do
    DbSupport.setup_db
  end
  config.around(:each) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end
end

RSpec::Support::ObjectFormatter.default_instance.max_formatted_output_length = 1000

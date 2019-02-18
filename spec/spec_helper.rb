require 'bundler/setup'

if (ENV['CI_JOB_NAME'] || '').include?('postgres_9_4')
  puts 'For Postgres 9.4 we cannot test que 1.x (as it uses new jsonb features), ' \
       'so we delete those appraisal files'
  exit(0) # Exit 0 so the CI build continues
end

require 'coveralls'
Coveralls.wear!

# By default, que-scheduler specs run in different timezones with every execution, thanks to
# zonebie. If you want to force one particular timezone, you can use the following:
# ENV['ZONEBIE_TZ'] = 'International Date Line West'
# Require zonebie before most other gems to ensure it sets the correct test timezone.
if ENV['CI'].present?
  # Changing the TZ in CI builds has proved to be hard, if not impossible. So, on CI only, shift
  # zonebie to using what is already present. For local builds, let zonebie randomise it.
  tz_identifier = `cat /etc/timezone`.strip
  puts "TZ appears to be #{tz_identifier}"
  ENV['ZONEBIE_TZ'] = tz_identifier
end
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
    qsa = Que::Scheduler::VersionSupport.execute('select * from que_scheduler_audit')
    expect(qsa.count).to eq(0)
    qsae = Que::Scheduler::VersionSupport.execute('select * from que_scheduler_audit_enqueued')
    expect(qsae.count).to eq(0)
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

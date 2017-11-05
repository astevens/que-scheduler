require 'que'
require 'yaml'
require 'backports/2.4.0/hash/compact'

require_relative 'defined_job'
require_relative 'schedule_parser'
require_relative 'scheduler_job_args'

module Que
  module Scheduler
    QUE_SCHEDULER_CONFIG_LOCATION =
      ENV.fetch('QUE_SCHEDULER_CONFIG_LOCATION', 'config/que_schedule.yml')

    class SchedulerJob < Que::Job
      SCHEDULER_FREQUENCY = 60

      # Highest possible priority.
      @priority = 0

      def run(options = nil, oldarg = nil)
        # Early versions took separate args. We now just pass in a hash.
        options = { last_run_time: options, job_dictionary: oldarg } if oldarg.present?

        ::ActiveRecord::Base.transaction do
          scheduler_job_args = SchedulerJobArgs.prepare_scheduler_job_args(options)
          logs = ["que-scheduler last ran at #{scheduler_job_args.last_run_time}."]

          # It's possible one worker node has severe clock skew, and reports a time earlier than
          # the last run. If so, log, and rescheduled with the same last run at.
          if scheduler_job_args.as_time < scheduler_job_args.last_run_time
            SchedulerJob.handle_clock_skew(scheduler_job_args, logs)
          else
            # Otherwise, run as normal
            SchedulerJob.handle_normal_call(scheduler_job_args, logs)
          end

          # Only now we're sure nothing errored, log the results
          logs.each { |str| Que.log(message: str) }
          destroy
        end
      end

      private

      class << self
        def scheduler_config
          @scheduler_config ||= begin
            jobs_list(YAML.load_file(QUE_SCHEDULER_CONFIG_LOCATION))
          end
        end

        # Convert the config hash into a list of real classes and args, parsing the cron and
        # "unmissable" parameters.
        def jobs_list(schedule)
          schedule.map do |k, v|
            Que::Scheduler::DefinedJob.new(
              {
                name: k,
                job_class: Object.const_get(v['class'] || k),
                queue: v['queue'],
                args: v['args'],
                priority: v['priority'],
                cron: v['cron'],
                unmissable: v['unmissable']
              }.compact
            )
          end
        end

        def handle_normal_call(scheduler_job_args, logs)
          result = enqueue_required_jobs(scheduler_job_args, logs)
          enqueue_self_again(
            scheduler_job_args.as_time,
            scheduler_job_args.as_time,
            result.schedule_dictionary
          )
        end

        def enqueue_required_jobs(scheduler_job_args, logs)
          # Obtain the hash of missed jobs. Keys are the job classes, and the values are arrays
          # each containing more arrays for the arguments of that instance.
          result = ScheduleParser.parse(SchedulerJob.scheduler_config, scheduler_job_args)
          result.missed_jobs.each do |job_class, args_arrays|
            args_arrays.each do |args|
              logs << "que-scheduler enqueueing #{job_class} with options: #{args}"
              job_class.enqueue(*args)
            end
          end
          result
        end

        def enqueue_self_again(last_full_execution, this_run_time, new_job_dictionary)
          SchedulerJob.enqueue(
            last_run_time: last_full_execution.iso8601,
            job_dictionary: new_job_dictionary,
            run_at: this_run_time.beginning_of_minute + SCHEDULER_FREQUENCY
          )
        end

        def handle_clock_skew(scheduler_job_args, logs)
          logs << 'que-scheduler detected worker with time older than last run. ' \
                      'Rescheduling without enqueueing jobs.'
          enqueue_self_again(
            scheduler_job_args.last_run_time,
            scheduler_job_args.as_time,
            scheduler_job_args.job_dictionary
          )
        end
      end
    end
  end
end

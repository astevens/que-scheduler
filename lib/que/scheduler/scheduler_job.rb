require 'que'

require_relative 'defined_job'
require_relative 'enqueueing_calculator'
require_relative 'scheduler_job_args'

# The main job that runs every minute, determining what needs to be enqueued, enqueues the required
# jobs, then re-enqueues itself.
module Que
  module Scheduler
    class SchedulerJob < Que::Job
      SCHEDULER_FREQUENCY = 60

      # Always highest possible priority.
      self.priority = 0

      def run(options = nil)
        ::Que.transaction do
          assert_one_scheduler_job
          scheduler_job_args = SchedulerJobArgs.build(options)
          logs = ["que-scheduler last ran at #{scheduler_job_args.last_run_time}."]

          result = EnqueueingCalculator.parse(DefinedJob.defined_jobs, scheduler_job_args)
          enqueue_required_jobs(result, logs)
          enqueue_self_again(scheduler_job_args, scheduler_job_args.as_time, result)

          # Only now we're sure nothing errored, log the results
          logs.each { |str| ::Que.log(event: 'que-scheduler'.to_sym, message: str) }
          destroy
        end
      end

      def enqueue_required_jobs(result, logs)
        result.missed_jobs.each do |to_enqueue|
          job_class = to_enqueue.job_class
          args = to_enqueue.args
          remaining_hash = to_enqueue.except(:job_class, :args)
          if args.is_a?(Hash)
            job_class.enqueue(args.merge(remaining_hash))
          else
            job_class.enqueue(*args, remaining_hash)
          end
          logs << "que-scheduler enqueueing #{job_class} with: #{to_enqueue}"
        end
      end

      private

      def assert_one_scheduler_job
        schedulers = Que::Scheduler::Db.count_schedulers
        return if schedulers == 1
        raise "Only one #{self.class.name} should be enqueued. #{schedulers} were found."
      end

      def enqueue_self_again(scheduler_job_args, last_full_execution, result)
        next_run_at = scheduler_job_args.as_time.beginning_of_minute + SCHEDULER_FREQUENCY
        SchedulerJob.enqueue(
          last_run_time: last_full_execution.iso8601,
          job_dictionary: result.job_dictionary,
          run_at: next_run_at
        )
        Audit.append(que_attrs.fetch(:id), scheduler_job_args.as_time, result)
      end
    end
  end
end

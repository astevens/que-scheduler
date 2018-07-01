require_relative 'audit'
require_relative 'db'
require_relative 'migrations'

module Que
  module Scheduler
    module StateChecks
      class << self
        def check
          assert_db_migrated
          assert_one_scheduler_job
        end

        private

        def assert_db_migrated
          db_version = Que::Scheduler::Migrations.db_version
          return if db_version == Que::Scheduler::Migrations::MAX_VERSION
          raise(<<-ERR)
            The que-scheduler db migration state was found to be #{db_version}. It should be #{Que::Scheduler::Migrations::MAX_VERSION}.

            que-scheduler adds some tables to the DB to provide an audit history of what was
            enqueued when, and with what options and arguments. The structure of these tables is
            versioned, and should match that version required by the gem.

            The currently migrated version of the audit tables is held in a table COMMENT (much like
            how que keeps track of its DB versions). You can check the current DB version by
            querying the COMMENT on the #{Que::Scheduler::Audit::TABLE_NAME} table like this:

            #{Que::Scheduler::Migrations::TABLE_COMMENT}

            Or you can use ruby:

              Que::Scheduler::Migrations.db_version

            To bring the db version up to the current one required, add a migration like this. It
            is cumulative, so one line is sufficient to perform all necessary steps.

            class UpdateQueSchedulerSchema < ActiveRecord::Migration
              def change
                Que::Scheduler::Migrations.migrate!(version: #{Que::Scheduler::Migrations::MAX_VERSION})
              end
            end
          ERR
        end

        def assert_one_scheduler_job
          schedulers = Que::Scheduler::Db.count_schedulers
          return if schedulers == 1
          raise(<<-ERR)
            Only one #{Que::Scheduler::SchedulerJob.name} should be enqueued. #{schedulers} were found.

            que-scheduler works by running a self-enqueueing version of itself that determines which
            jobs should be enqueued based on the provided config. If two or more que-schedulers were
            to run at once, then duplicate jobs would occur.

            To resolve this problem, please remove any duplicate scheduler jobs from the que_jobs table.
          ERR
        end
      end
    end
  end
end

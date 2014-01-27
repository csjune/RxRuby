# Copyright (c) Microsoft Open Technologies, Inc. All rights reserved. See License.txt in the project root for license information.

require 'singleton'
require 'thread'
require 'rx/internal/priority_queue'
require 'rx/concurrency/local_scheduler'
require 'rx/concurrency/scheduled_item'
require 'rx/disposables/disposable'
require 'rx/disposables/single_assignment_disposable'
require 'rx/disposables/composite_disposable'

module RX

    # Represents an object that schedules units of work on the platform's default scheduler.
    class CurrentThreadScheduler < RX::LocalScheduler

        include Singleton

        @@thread_local_queue = nil

        # Gets a value that indicates whether the caller must call a Schedule method.
        def schedule_required?
            @@thread_local_queue.nil?
        end

        # Schedules an action to be executed after dueTime.
        def schedule_relative_with_state(state, due_time, action)
            raise 'action cannot be nil' unless action

            dt = self.now.to_i + Scheduler.normalize(due_time)
            si = ScheduledItem.new self, state, action, dt

            local_queue = self.class.queue

            unless local_queue
                local_queue = PriorityQueue.new 4
                local_queue.push si

                self.class.queue = local_queue

                begin
                    Trampoline.run local_queue
                ensure
                    self.class.queue = nil
                end
            else
                local_queue.push si
            end

            Disposable.create { si.cancel }
        end

        private

        def self.queue
            @@thread_local_queue
        end

        def self.queue=(new_queue)
            @@thread_local_queue = new_queue
        end

        class Trampoline

            def self.run(queue)
                while queue.length > 0
                    item = queue.shift
                    unless item.cancelled?
                        wait = item.due_time - Scheduler.now.to_i
                        sleep wait if wait > 0
                        item.invoke unless item.cancelled?
                    end
                end
            end

        end

    end

end
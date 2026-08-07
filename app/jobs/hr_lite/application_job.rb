module HrLite
  # Parent of the engine's jobs. It existed but nothing inherited from it, so
  # no retry policy applied anywhere: a digest or a rollover that hit a
  # dropped connection was simply lost for that day — or for that year.
  class ApplicationJob < ActiveJob::Base
    retry_on ActiveRecord::ConnectionNotEstablished, ActiveRecord::Deadlocked,
             wait: :polynomially_longer, attempts: 5
  end
end

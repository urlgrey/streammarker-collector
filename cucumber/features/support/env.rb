require 'net/http'
require 'fileutils'
require 'childprocess'
require 'tempfile'
require 'httparty'
require 'json_spec'
require 'erubis'
require 'aws-sdk-v1'
require 'aws-sdk'
require 'json'

require_relative 'feature_helper'

# Setup JSON Spec in a way which doesn't pull in Cucumber definitions which can conflict with our own.
# Also set it to ignore some fields by default.
World(JsonSpec::Helpers, JsonSpec::Matchers)
JsonSpec.configure do
  exclude_keys 'created_at', 'updated_at'
end

APPLICATION_ENDPOINT = 'http://localhost:3000'
HEALTHCHECK_ENDPOINT = 'http://localhost:3100'
LOG_DIR = 'cuke-logs'
CUCUMBER_BASE = '.'
APPLICATION_LOG_FILE = File.join(LOG_DIR, 'application.log')

FAKEDYNAMO_ROOT = Tempfile.new('dynamo').path # TODO: Clean me up
FAKEDYNAMO_HOST = 'localhost'
FAKEDYNAMO_PORT = '10040'

FAKESQS_HOST = 'localhost'
FAKESQS_PORT = '10030'

ENV['AWS_ACCESS_KEY_ID'] = "a"
ENV['AWS_SECRET_ACCESS_KEY'] = "b"
ENV['AWS_REGION'] = 'us-east-1'

STREAMMARKER_QUEUE_NAME = 'Queue'
ENV['STREAMMARKER_SQS_ENDPOINT'] = "http://#{FAKESQS_HOST}:#{FAKESQS_PORT}"
ENV['STREAMMARKER_QUEUE_NAME'] = "Queue"
ENV['STREAMMARKER_SQS_QUEUE_URL'] = ENV['STREAMMARKER_SQS_ENDPOINT'] + '/' + STREAMMARKER_QUEUE_NAME
ENV['STREAMMARKER_COLLECTOR_API_TOKENS'] = 'secret_key'

def wait_till_up_or_timeout
  healthy = false
  i = 0
  puts 'Waiting for system under test to start...'
  while (!healthy) && i < 30 do

    unless @app_process.alive?
      shutdown
      raise "The Application's child process exited undepectedly. Check #{APPLICATION_LOG_FILE} for details"
    end

    begin
      response = Net::HTTP.get_response(URI.parse(HEALTHCHECK_ENDPOINT + '/healthcheck'))
      if response.code == '200'
        healthy = true
      else
        puts 'Health check returned status code: ' + response.code
      end
    rescue Exception => e
      puts 'Encountered exception while polling Health check URL: ' + e.to_s
    end
    i = i + 1
    sleep(1) unless healthy
  end

  unless healthy
    shutdown
    raise 'Application failed to pass healthchecks within an acceptable amount of time. Declining to run tests.'
  end
end

def startup

  @fakesqs_process = ChildProcess.build('fake_sqs', '-p', FAKESQS_PORT)
  @fakesqs_process.io.stdout = File.new(LOG_DIR + '/fakesqs.log', 'w')
  @fakesqs_process.io.stderr = @fakesqs_process.io.stdout
  @fakesqs_process.leader = true
  @fakesqs_process.start

  # Give Fake SQS a sec to start, and create the queue we're about to use in it.
  sleep(1)
  sqs = AWS::SQS.new(:access_key_id       => 'x',
                       :secret_access_key => 'y',
                       :use_ssl           => false,
                       :sqs_endpoint      => FAKESQS_HOST,
                       :sqs_port          => FAKESQS_PORT.to_i
                       )
  sqs.client.create_queue(queue_name: STREAMMARKER_QUEUE_NAME)

  puts 'Forking to start application under test'
  @app_process = ChildProcess.build('go', 'run', '../collector.go')
  @app_process.io.stdout = File.new(APPLICATION_LOG_FILE, 'w')
  @app_process.io.stderr = @app_process.io.stdout
  @app_process.leader = true
  @app_process.start
end

def shutdown
  @app_process.stop
  @fakesqs_process.stop
end

# Cucumber entry point

puts 'Application Endpoint: ' + APPLICATION_ENDPOINT.to_s
puts 'Log Directory: ' + LOG_DIR.to_s
puts "fakesqs running at: #{FAKESQS_HOST}:#{FAKESQS_PORT}"

AWS.config(use_ssl: false, :access_key_id => 'x', :secret_access_key => 'y')

startup
wait_till_up_or_timeout

# ----- Cucumber Hooks ----- #

# Hook Cucumber exiting
at_exit do
  shutdown
end

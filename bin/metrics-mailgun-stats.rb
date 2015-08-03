#!/usr/bin/env ruby

require 'sensu-plugin/metric/cli'
require 'net/http'
require 'json'
require 'time'
require 'aws-sdk-core'
require '../lib/sensu-plugins-mailgun/common.rb'

class MetricsMailgunStats < Sensu::Plugin::Metric::CLI::Graphite
  include Common
  option :aws_access_key,
         short:       '-a AWS_ACCESS_KEY',
         long:        '--aws-access-key AWS_ACCESS_KEY',
         description: "AWS Access Key. Either set ENV['AWS_ACCESS_KEY'] or provide it as an option",
         default:     ENV['AWS_ACCESS_KEY']

  option :aws_secret_access_key,
         short:       '-k AWS_SECRET_KEY',
         long:        '--aws-secret-access-key AWS_SECRET_KEY',
         description: "AWS Secret Access Key. Either set ENV['AWS_SECRET_KEY'] or provide it as an option",
         default:     ENV['AWS_SECRET_KEY']

  option :aws_region,
         short:       '-r AWS_REGION',
         long:        '--aws-region REGION',
         description: 'AWS Region (defaults to us-east-1).',
         default:     'us-east-1'

  option :s3_config_bucket,
         short:       '-s S3_CONFIG_FILE',
         long:        '--s3-config-file S3_CONFIG_FILE',
         description: 'S3 config bucket'

  option :s3_config_key,
         short:       '-k S3_CONFIG_KEY',
         long:        '--s3-config-KEY S3_CONFIG_KEY',
         description: 'S3 config key'

  option :domains,
         short:       '-q DOMAIN',
         long:        '--domains DOMAIN',
         description: 'Comma separated list of Mailgun domains to check',
         required: true,
         proc: Proc.new { |d| d.split(",") }

  option :events,
         short:       '-e EVENT',
         long:        '--events EVENT',
         default: ['sent'],
         proc: Proc.new { |d| d.split(",") },
         description: 'Comma separated list of Mailgun events to check. Defaults to "sent"'

  option :tags,
         short:       '-t TAGS',
         long:        '--tags TAGS',
         default: [],
         proc: Proc.new { |d| d.split(",") },
         description: 'Comma separated list of Mailgun tags to filter by.'

  option :start_date,
         long:        '--start-date START_DATE',
         description: 'The date to receive the stats starting from. YYYY-mm-DD'

  option :since_last_execution,
         long:        '--since-last-execution',
         boolean: true,
         description: 'If the start date should be the last '

  option :scheme,
         description: 'Metric naming scheme',
         long: '--scheme SCHEME',
         default: "#{Socket.gethostname}.mailgun.aggregates"

  def run
    aws_config
    merge_s3_config

    totalSent = getTotalSent config[:domains], config[:mailgunKey], config[:events], config[:tags]

    output "#{config[:scheme]}", totalSent, Time.now.utc

    ok
  end

  def getTotalSent(domains, mailgunKey, events, tags)
    sent = domains.map do |domain|
      begin
        uri = URI("https://api.mailgun.net/v3/#{domain}/stats?#{events.map{|e|"event=#{e}"}.join("&")}&limit=1")
        # uri = URI("https://api.mailgun.net/beta/#{domain}/stats/total?event=#{event}&duration=2d")
        req = Net::HTTP::Get.new(uri)
        req.basic_auth 'api', mailgunKey

        http = Net::HTTP.new(uri.hostname, uri.port)
        http.use_ssl = true

        res = http.request(req)
      rescue => e
          critical "Error talking to Mailgun API #{e}"
      end
      JSON.parse res.body
    end

    counts = sent.map do |item|
      puts "#{item}"
      if item != nil
        if (tags != nil && !tags.empty? && !(tags.length == 1 && tags[0] == ""))
            tags.map {|tag| item['items'][0]['tags'][tag] }.select{|v| !v.nil?}.inject(0) {|x, y| x + y}
        else
            item['items'][0]['total_count']
        end
      else
        0
      end
    end
    counts.inject(0) {|x, y| x + y}
  end
end

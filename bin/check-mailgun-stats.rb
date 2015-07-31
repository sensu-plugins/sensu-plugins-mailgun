#!/usr/bin/env ruby

require 'sensu-plugin/check/cli'
require 'net/http'
require 'json'
require 'time'
require 'aws-sdk-core'
require 'sensu-plugins-mailgun'

class CheckEmailTotals < Sensu::Plugin::Check::CLI
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

  option :day_of_week,
         short:       '-d DAY_OF_WEEK',
         long:        '--day-of-week DAY_OF_WEEK',
         description: 'Day of week to run check',
         proc: proc(&:to_i)

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

  option :day_of_month,
         short:       '-m DAY_OF_MONTH',
         long:        '--day-of-month DAY_OF_MONTH',
         description: 'Day of month to run check',
         proc: proc(&:to_i)

  option :hour_of_day,
         short:       '-h HOUR_OF_DAY',
         long:        '--hour-of-day HOUR_OF_DAY',
         description: 'Hours of day to run check, utc',
         default: 20,
         proc: proc(&:to_i)

  option :critical,
         description: 'Count to critical at or below',
         short: '-c COUNT',
         long: '--critical COUNT',
         default: 0,
         proc: proc(&:to_i)

  option :warning,
         description: 'Count to warn at or below',
         short: '-w WARNING',
         long: '--warning WARNING',
         default: 0,
         proc: proc(&:to_i)

  option :invert,
         description: 'Invert thresholds to be maximums instead of minimums',
         short: '-i',
         long: '--invert',
         default: false,
         boolean: true

  def run
    curr_time = Time.now.utc
    if curr_time.hour != config[:hour_of_day]
      ok
    end

    if config[:day_of_week] != nil && curr_time.wday != config[:day_of_week]
      ok
    end

    if config[:day_of_month] != nil && curr_time.day != config[:day_of_month]
      ok
    end

    aws_config
    merge_s3_config

    totalSent = getTotalSent config[:domains], config["mailgunKey"], config[:events], config[:tags]

    critical "Expected #{expectedEmails} sent, got #{totalSent}" if totalSent <= config[:critical] && !config[:invert]
    critical "Expected #{expectedEmails} sent, got #{totalSent}" if totalSent > config[:critical] && config[:invert]

    warning "Expected #{expectedEmails} sent, got #{totalSent}" if totalSent <= config[:warning] && !config[:invert]
    warning "Expected #{expectedEmails} sent, got #{totalSent}" if totalSent > config[:warning] && config[:invert]

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

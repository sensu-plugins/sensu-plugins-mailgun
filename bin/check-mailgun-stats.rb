#!/usr/bin/env ruby

require 'sensu-plugin/check/cli'
require 'net/http'
require 'json'
require 'time'
require 'aws-sdk-core'
require 'tz'
require 'sensu-plugins-mailgun'

class CheckMailgunTotals < Sensu::Plugin::Check::CLI
  include Common

  option :domains,
         short:       '-q DOMAIN',
         long:        '--domains DOMAIN',
         description: 'Comma separated list of Mailgun domains to check',
         required: true,
         proc: proc { |d| d.split(',') }

  option :events,
         short:       '-e EVENT',
         long:        '--events EVENT',
         default: ['sent'],
         proc: proc { |d| d.split(',') },
         description: 'Comma separated list of Mailgun events to check. Defaults to "sent"'

  option :tags,
         short:       '-t TAGS',
         long:        '--tags TAGS',
         default: [],
         proc: proc { |d| d.split(',') },
         description: 'Comma separated list of Mailgun tags to filter by.'

  option :start_date,
         long:        '--start-date START_DATE',
         description: 'The date to receive the stats starting from. YYYY-mm-DD'

  option :day_of_month,
         short:       '-m DAY_OF_MONTH',
         long:        '--day-of-month DAY_OF_MONTH',
         description: 'Day of month to run check',
         proc: proc(&:to_i)

  option :day_of_week,
         short:       '-d DAY_OF_WEEK',
         long:        '--day-of-week DAY_OF_WEEK',
         description: 'Day of week to run check',
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

  option :timezone,
         short:       '-z TIMEZONE',
         long:        '--timezone TIMEZONE',
         default: 'America/New_York',
         description: 'Timezone to use from ruby gem tz'

  def run
    curr_time = TZInfo::Timezone.get(config[:timezone]).now
    if curr_time.hour != config[:hour_of_day]
      ok
    end

    if !config[:day_of_week].nil? && curr_time.wday != config[:day_of_week]
      ok
    end

    if !config[:day_of_month].nil? && curr_time.day != config[:day_of_month]
      ok
    end

    merge_s3_config

    total_sen = gettotal_sen config[:domains], config[:mailgunKey], config[:events], config[:tags], config[:start_date]

    critical "Expected #{config[:critical]} sent, got #{total_sen}" if total_sen <= config[:critical] && !config[:invert]
    critical "Expected #{config[:critical]} sent, got #{total_sen}" if total_sen > config[:critical] && config[:invert]

    warning "Expected #{config[:warning]} sent, got #{total_sen}" if total_sen <= config[:warning] && !config[:invert]
    warning "Expected #{config[:warning]} sent, got #{total_sen}" if total_sen > config[:warning] && config[:invert]

    ok
  end

  def gettotal_sen(domains, mailgun_key, events, tags, start_date)
    sent = domains.map do |domain|
      begin
        start_date_string = !start_date.nil? ? "&#{start_date}" : ''
        uri = URI("https://api.mailgun.net/v3/#{domain}/stats?#{events.map { |e| "event=#{e}" }.join('&')}&limit=1#{start_date_string}")
        # uri = URI("https://api.mailgun.net/beta/#{domain}/stats/total?event=#{event}&duration=2d")
        req = Net::HTTP::Get.new(uri)
        req.basic_auth 'api', mailgun_key

        http = Net::HTTP.new(uri.hostname, uri.port)
        http.use_ssl = true

        res = http.request(req)
      rescue => e
        critical "Error talking to Mailgun API #{e}"
      end
      JSON.parse res.body
    end

    counts = sent.map do |item|
      if !item.nil?
        if !tags.nil? && !tags.empty? && !(tags.length == 1 && tags[0] == '')
          tags.map { |tag| item['items'][0]['tags'][tag] }.select { |v| !v.nil? }.inject(0) { |x, y| x + y }
        else
          item['items'][0]['total_count']
        end
      else
        0
      end
    end
    counts.inject(0) { |x, y| x + y }
  end
end

#!/usr/bin/env ruby
#
#   metrics-mailgun-stats.rb
#
# DESCRIPTION:
#
#
# OUTPUT:
#   metric data
#
# PLATFORMS:
#   Ruby environment that supports gem dependencies
#
# DEPENDENCIES:
#   gem: sensu-plugin, aws-sdk
#
# USAGE:
#
# NOTES:
#
# LICENSE:
#   Leon Gibat brendan.gibat@gmail.com
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.

require 'sensu-plugin/metric/cli'
require 'net/http'
require 'json'
require 'time'
require '../lib/sensu-plugins-mailgun/common.rb'

class MetricsMailgunStats < Sensu::Plugin::Metric::CLI::Graphite
  include Common

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
    merge_s3_config

    totalSent = getTotalSent config[:domains], config[:mailgunKey], config[:events], config[:tags]

    output "#{config[:scheme]}", totalSent, Time.now.utc

    ok
  end

  def getTotalSent(domains, mailgunKey, events, tags)
    sent = domains.map do |domain|
      begin
        uri = URI("https://api.mailgun.net/v3/#{domain}/stats?#{events.map{|e|"event=#{e}"}.join("&")}&limit=1")
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

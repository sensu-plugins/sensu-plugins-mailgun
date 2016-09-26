
module Common
  def initialize
    super()
  end

  def get_check_last_runtime(client, check)
    request = RestClient::Resource.new(
      "#{config[:sensu_scheme]}://#{config[:sensu_api]}:#{config[:sensu_port]}/#{client}/#{check}",
      timeout: config[:sensu_timeout],
      user: config[:sensu_user],
      password: config[:sensu_password]
    )
    check = JSON.parse(request.get, symbolize_names: true)
    Time.at(check[:check][:issued])
  rescue RestClient::ResourceNotFound
    nil
  rescue Errno::ECONNREFUSED
    warning 'Connection refused'
  rescue RestClient::RequestFailed
    warning 'Request failed'
  rescue RestClient::RequestTimeout
    warning 'Connection timed out'
  rescue RestClient::Unauthorized
    warning 'Missing or incorrect Sensu API credentials'
  rescue JSON::ParserError
    warning 'Sensu API returned invalid JSON'
  end
end

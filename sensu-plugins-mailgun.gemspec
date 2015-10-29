lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'date'

if RUBY_VERSION < '2.0.0'
  require 'sensu-plugins-mailgun'
else
  require_relative 'lib/sensu-plugins-mailgun'
end

Gem::Specification.new do |s|
  s.name               = 'sensu-plugins-mailgun'
  s.version            = '0.1.0'
  s.licenses           = ['MIT']
  s.summary            = "Sensu plugin for getting stats from the MailGun API"
  s.description        = "I need dis"
  s.authors            = ["Dreae"]
  s.email              = 'thedreae@gmail.com'
  s.executables        = Dir.glob('bin/**/*.rb').map { |file| File.basename(file) }
  s.require_paths      = ['lib']
  s.files              = Dir.glob('{bin,lib}/**/*')

  s.add_runtime_dependency 'sensu-plugin',      '1.1.0'
  s.add_runtime_dependency 'json',              '1.8.3'
  s.add_runtime_dependency 'aws-sdk-core',      '2.1.33'
  s.add_runtime_dependency 'tz',                '0.0.1'
  s.add_runtime_dependency 'tzinfo',            '1.2.2'
end

# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'flexirest/version'

Gem::Specification.new do |spec|
  spec.name          = "flexirest"
  spec.version       = Flexirest::VERSION
  spec.platform      = Gem::Platform::RUBY
  spec.authors       = ["Andy Jeffries"]
  spec.email         = ["andy@andyjeffries.co.uk"]
  spec.description   = %q{Accessing REST services in a flexible way}
  spec.summary       = %q{This gem is for accessing REST services in a flexible way.  ActiveResource already exists for this, but it doesn't work where the resource naming doesn't follow Rails conventions, it doesn't have in-built caching and it's not as flexible in general.}
  spec.homepage      = "https://andyjeffries.co.uk/"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec", "~> 3"
  spec.add_development_dependency "webmock"
  spec.add_development_dependency "rspec_junit_formatter"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "simplecov-rcov"
  spec.add_development_dependency "guard-rspec"
  spec.add_development_dependency 'terminal-notifier-guard'
  spec.add_development_dependency 'coveralls'
  spec.add_development_dependency "api-auth", ">= 1.3.1"
  spec.add_development_dependency 'typhoeus'

  spec.add_runtime_dependency "multi_json"
  spec.add_runtime_dependency "crack"
  spec.add_runtime_dependency "activesupport"
  spec.add_runtime_dependency "faraday"
end
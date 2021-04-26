# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

require "xingfus/version"

Gem::Specification.new do |gem|
  gem.name        = "xingfus"
  gem.authors     = ["Stefan Kaes", "Larry Baltz", "Mark Schmidt", "Sebastian Röbke", "Paul Dix", "David Balatero"]
  gem.email       = ["stefan.kaes@xing.com", "larry.baltz@xing.com", "mark.schmidt@xing.com", "sebastian.roebke@xing.com"]
  gem.description = "Like a modern code version of the mythical beast with 100 serpent heads, Xingfus runs HTTP requests in parallel while cleanly encapsulating handling logic."
  gem.summary     = "A library for interacting with web services (and building SOAs) at blinding speed. XING fork."
  gem.homepage    = "https://github.com/xing/xingfus"
  gem.license     = "MIT"
  gem.version     = Xingfus::VERSION

  gem.extensions    = ["ext/typhoeus/extconf.rb"]
  gem.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  gem.files         = `git ls-files`.split("\n")
  gem.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  gem.require_paths = ["lib"]

  gem.extra_rdoc_files = ["LICENSE", "README.textile"]
  gem.rdoc_options     = ["--charset=UTF-8"]

  gem.add_dependency "mime-types"

  gem.add_development_dependency "rake", "~> 10.5"
  gem.add_development_dependency "rspec", "~> 2.14.0"
  gem.add_development_dependency "sinatra"
  gem.add_development_dependency "json"
end

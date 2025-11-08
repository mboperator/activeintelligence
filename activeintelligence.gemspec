require_relative "lib/version"

Gem::Specification.new do |spec|
  spec.name = "activeintelligence.rb"
  spec.version = ActiveIntelligence::VERSION
  spec.authors = ["Marcus Bernales"]
  spec.email = ["marcus@totum.io"]

  spec.summary = "A Ruby gem for building AI agents powered by Claude (Anthropic's LLM)"
  spec.description = "ActiveIntelligence provides a clean DSL for creating conversational AI agents with tool calling, memory management, and both static and streaming response modes."
  spec.homepage = "https://github.com/mboperator/activeintelligence"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = "bin"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  # No hard dependencies - stdlib only for CLI usage

  # Development dependencies
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.0"
  spec.add_development_dependency "pry", "~> 0.14"

  # Optional Rails integration dependencies
  # When using :active_record memory strategy, ensure you have:
  # - activerecord (>= 6.0)
  # - activesupport (>= 6.0)
  # These are not hard dependencies to keep the gem lightweight for CLI usage
end
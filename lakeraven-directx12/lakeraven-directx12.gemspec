# frozen_string_literal: true

require_relative "lib/lakeraven/directx12/version"

Gem::Specification.new do |spec|
  spec.name        = "lakeraven-directx12"
  spec.version     = Lakeraven::DirectX12::VERSION
  spec.authors     = ["Lakeraven"]
  spec.email       = ["eng@lakeraven.com"]
  spec.homepage    = "https://github.com/lakeraven/lakeraven-integrations"
  spec.summary     = "Raw X12 EDI adapter for Lakeraven integrations (vendor-lock hedge)"
  spec.description = "Implements Lakeraven::Integrations::Edi::Base by generating " \
                     "raw X12 transactions and submitting via configurable transport " \
                     "(SFTP, AS2, HTTPS). Works with any clearinghouse that accepts " \
                     "standard X12 270/837/276/835 transactions. Serves as the public " \
                     "vendor-lock hedge: any Lakeraven customer can self-host the " \
                     "public stack and bring their own clearinghouse contract."
  spec.license     = "MIT"
  spec.metadata    = {
    "homepage_uri"      => "https://github.com/lakeraven/lakeraven-integrations",
    "source_code_uri"   => "https://github.com/lakeraven/lakeraven-integrations/tree/main/lakeraven-directx12"
  }

  spec.required_ruby_version = ">= 3.4.0"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["lib/**/*", "README.md"]
  end

  spec.require_paths = ["lib"]

  spec.add_dependency "lakeraven-integrations", "~> 0.1"
end

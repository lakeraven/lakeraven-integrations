# frozen_string_literal: true

require "test_helper"

module Lakeraven
  module Integrations
    module Edi
      class BaseTest < Minitest::Test
        def setup
          @edi = Base.new
        end

        def test_check_eligibility_raises_not_implemented
          request = Lakeraven::Fhir::CoverageEligibilityRequest.new(
            patient_dfn: "123", coverage_type: "medicaid"
          )
          assert_raises(NotImplementedError) { @edi.check_eligibility(request) }
        end

        def test_submit_claim_raises_not_implemented
          claim = Lakeraven::Fhir::Claim.new(claim_type: "837P", patient_dfn: "123")
          assert_raises(NotImplementedError) { @edi.submit_claim(claim) }
        end

        def test_check_claim_status_raises_not_implemented
          assert_raises(NotImplementedError) { @edi.check_claim_status("CLM-001") }
        end

        def test_process_remittance_raises_not_implemented
          assert_raises(NotImplementedError) { @edi.process_remittance("REM-001") }
        end
      end

      # -- Lakeraven::Integrations configuration registry --

      class ConfigurationTest < Minitest::Test
        def teardown
          Lakeraven::Integrations.reset_configuration!
        end

        def test_configure_sets_edi_adapter
          mock = Mock.new
          Lakeraven::Integrations.configure do |config|
            config.edi_adapter = mock
          end

          assert_equal mock, Lakeraven::Integrations.edi_adapter
        end

        def test_edi_adapter_returns_nil_when_not_configured
          assert_nil Lakeraven::Integrations.edi_adapter
        end

        def test_reset_configuration_clears_adapters
          Lakeraven::Integrations.configure { |c| c.edi_adapter = Mock.new }
          Lakeraven::Integrations.reset_configuration!

          assert_nil Lakeraven::Integrations.edi_adapter
        end

        def test_configure_yields_configuration_object
          Lakeraven::Integrations.configure do |config|
            assert_instance_of Lakeraven::Integrations::Configuration, config
          end
        end
      end
    end
  end
end

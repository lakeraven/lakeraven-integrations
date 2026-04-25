# frozen_string_literal: true

require "test_helper"

module Lakeraven
  module Integrations
    module Clinical
      class PatientLookupBaseTest < Minitest::Test
        def setup
          @lookup = PatientLookup::Base.new
        end

        def test_find_raises_not_implemented
          assert_raises(NotImplementedError) { @lookup.find(1) }
        end

        def test_search_raises_not_implemented
          assert_raises(NotImplementedError) { @lookup.search("DOE") }
        end

        def test_find_by_ssn_raises_not_implemented
          assert_raises(NotImplementedError) { @lookup.find_by_ssn("111-11-1111") }
        end
      end

      class PatientLookupMockTest < Minitest::Test
        def setup
          @mock = PatientLookup::Mock.new
          @mock.seed(dfn: 1, name: "DOE,JOHN", ssn: "111-11-1111")
          @mock.seed(dfn: 2, name: "SMITH,JANE", ssn: "222-22-2222")
        end

        def test_find_returns_seeded_patient
          result = @mock.find(1)
          assert_equal "DOE,JOHN", result[:name]
          assert_equal 1, result[:dfn]
        end

        def test_find_returns_nil_for_unknown_dfn
          assert_nil @mock.find(999)
        end

        def test_search_filters_by_name_prefix
          results = @mock.search("DOE")
          assert_equal 1, results.length
          assert_equal "DOE,JOHN", results.first[:name]
        end

        def test_search_empty_string_returns_all
          results = @mock.search("")
          assert_equal 2, results.length
        end

        def test_find_by_ssn_returns_match
          result = @mock.find_by_ssn("222-22-2222")
          assert_equal "SMITH,JANE", result[:name]
        end

        def test_find_by_ssn_returns_nil_for_unknown
          assert_nil @mock.find_by_ssn("999-99-9999")
        end
      end
    end
  end
end

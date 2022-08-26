require "simplecov"
SimpleCov.start

require "webmock/rspec"
require "climate_control"
require_relative "../lib/requires"

RSpec.configure do |config|
  # rspec-expectations config goes here. You can use an alternate
  # assertion/expectation library such as wrong or the stdlib/minitest
  # assertions if you prefer.
  config.expect_with :rspec do |expectations|
    # This option will default to `true` in RSpec 4. It makes the `description`
    # and `failure_message` of custom matchers include text for helper methods
    # defined using `chain`, e.g.:
    #     be_bigger_than(2).and_smaller_than(4).description
    #     # => "be bigger than 2 and smaller than 4"
    # ...rather than:
    #     # => "be bigger than 2"
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  # rspec-mocks config goes here. You can use an alternate test double
  # library (such as bogus or mocha) by changing the `mock_with` option here.
  config.mock_with :rspec do |mocks|
    # Prevents you from mocking or stubbing a method that does not exist on
    # a real object. This is generally recommended, and will default to
    # `true` in RSpec 4.
    mocks.verify_partial_doubles = true
  end

  # This option will default to `:apply_to_host_groups` in RSpec 4 (and will
  # have no way to turn it off -- the option exists only for backwards
  # compatibility in RSpec 3). It causes shared context metadata to be
  # inherited by the metadata hash of host groups and examples, rather than
  # triggering implicit auto-inclusion in groups with matching metadata.
  config.shared_context_metadata_behavior = :apply_to_host_groups
end

def stub_fastly_get_service(service_id)
  requests = []

  # Fastly#get_service. Return a service with two VCL "versions" (https://docs.fastly.com/api/config#version)
  requests << stub_request(:get, "https://api.fastly.com/service/#{service_id}")
    .to_return(body: File.read("spec/fixtures/fastly-get-service-response.json"))

  # We clone the latest active VCL version, which returns the latest version
  requests << stub_request(:put, "https://api.fastly.com/service/#{service_id}/version/2/clone")
    .to_return(body: File.read("spec/fixtures/fastly-put-clone.json"))
end

def stub_fastly_delete_old_vcl(service_id, service_types)
  requests = []
  # Stub calls to delete the "UI objects"
  service_types.each do |thing|
    requests << stub_request(:get, "https://api.fastly.com/service/#{service_id}/version/3/#{thing}")
      .to_return(body: "{}")
  end
  requests
end

def stub_fastly_unsuccessfully_delete_old_vcl(service_id, service_type)
  requests = []
  # Stub calls to get the "UI objects"
  requests << stub_request(:get, "https://api.fastly.com/service/#{service_id}/version/3/#{service_type}")
  .to_return(body: JSON.dump([{ name: "old.example.com" }]))

  # Stub calls to delete the "UI objects"
  requests << stub_request(:delete, "https://api.fastly.com/service/#{service_id}/version/3/#{service_type}/old.example.com")
    .to_return(status: 500)
end

def stub_fastly_handle_transition_hosts(service_id)
  requests = []

  # Given Transition has 2 hosts
  requests << stub_request(:get, "https://transition.publishing.service.gov.uk/hosts.json")
  .to_return(body: JSON.dump(results: [{ hostname: "existing.example.com" }, { hostname: "newly-added.example.com" }]))

  # And Fastly has 2 hosts, but one is different from transition
  requests << stub_request(:get, "https://api.fastly.com/service/#{service_id}/version/3/domain")
    .to_return(body: JSON.dump([{ name: "existing.example.com" }, { name: "old.example.com" }]))

  # One domain will be deleted
  requests << stub_request(:delete, "https://api.fastly.com/service/#{service_id}/version/3/domain/old.example.com")
    .to_return(body: "{}")

  # And the new one will be created
  requests << stub_request(:post, "https://api.fastly.com/service/#{service_id}/version/3/domain")
    .with(
      body: { "comment" => "", "name" => "newly-added.example.com", "service_id" => service_id, "version" => "3" },
    )
    .to_return(body: "{}")
end

def stub_fastly_upload_new_vcl(service_id)
  requests = []
  # We first check the latest version
  requests << stub_request(:get, "https://api.fastly.com/service/#{service_id}/version/3/vcl/main")
   .to_return(body: "{}")

  # We then delete it
  requests << stub_request(:delete, "https://api.fastly.com/service/#{service_id}/version/3/vcl/main")
    .to_return(body: "{}")

  # Then send the actual VCL
  # https://docs.fastly.com/api/config#vcl_7ade6ab5926b903b6acf3335a85060cc
  requests << stub_request(:post, "https://api.fastly.com/service/#{service_id}/version/3/vcl")
    .to_return(body: File.read("spec/fixtures/fastly-post-vcl.json"))

  # Test the VCL of the previous version
  requests << stub_request(:put, "https://api.fastly.com/service/#{service_id}/version/2/vcl/test-vcl/main")
    .to_return(body: "{}")

  requests << stub_request(:get, "https://api.fastly.com/service/#{service_id}/version/2/generated_vcl")
    .to_return(body: "{}")

  requests << stub_request(:get, "https://api.fastly.com/service/#{service_id}/version/3/generated_vcl")
    .to_return(body: "{}")
end

def stub_fastly_activate_new_vcl(service_id)
  # Activate the version we've just created
  stub_request(:put, "https://api.fastly.com/service/#{service_id}/version/3/activate")
    .to_return(body: "{}")
end

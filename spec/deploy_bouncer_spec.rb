require './lib/deploy_bouncer'

describe DeployBouncer do
  describe '#deploy' do
    it 'deploys the VCL for bouncer' do
      @requests = []

      # This call is made by the Fastly library when you call `Fastly.new`
      @requests << stub_request(:post, "https://api.fastly.com/login").to_return(body: "{}")

      # Fastly#get_service. Return a service with two VCL "versions" (https://docs.fastly.com/api/config#version)
      @requests << stub_request(:get, "https://api.fastly.com/service/123321abc").
        to_return(body: File.read("spec/fixtures/fastly-get-service-response.json"))

      # We clone the latest active VCL version, which returns the latest version
      @requests << stub_request(:put, "https://api.fastly.com/service/123321abc/version/2/clone").
        to_return(body: File.read("spec/fixtures/fastly-put-clone.json"))

      # Given Transition has 2 hosts
      @requests << stub_request(:get, "https://transition.publishing.service.gov.uk/hosts.json").
        to_return(body: JSON.dump(results: [{ hostname: "existing.example.com" }, { hostname: "newly-added.example.com" }]))

      # And Fastly has 2 hosts, but one is different from transition
      @requests << stub_request(:get, "https://api.fastly.com/service/123321abc/version/3/domain").
        to_return(body: JSON.dump([{ name: "existing.example.com" }, { name: "old.example.com" }]))

      # One domain will be deleted
      @requests << stub_request(:delete, "https://api.fastly.com/service/123321abc/version/3/domain/old.example.com").
        to_return(body: "{}")

      # And the new one will be created
      @requests << stub_request(:post, "https://api.fastly.com/service/123321abc/version/3/domain").
        with(
          body: { "comment" => "", "name" => "newly-added.example.com", "service_id" => "123321abc", "version" => "3" }
        ).
        to_return(body: "{}")

      # Stub calls to delete the "UI objects"
      %w[backend healthcheck cache_settings condition request_settings response_object header gzip].each do |thing|
        @requests << stub_request(:get, "https://api.fastly.com/service/123321abc/version/3/#{thing}").
          to_return(body: "{}")
      end

      # We first check the latest version
      @requests << stub_request(:get, "https://api.fastly.com/service/123321abc/version/3/vcl/main").
        to_return(body: "{}")

      # We then delete it
      @requests << stub_request(:delete, "https://api.fastly.com/service/123321abc/version/3/vcl/main").
        to_return(body: "{}")

      # Then send the actual VCL
      # https://docs.fastly.com/api/config#vcl_7ade6ab5926b903b6acf3335a85060cc
      @requests << stub_request(:post, "https://api.fastly.com/service/123321abc/version/3/vcl").
        to_return(body: File.read("spec/fixtures/fastly-post-vcl.json"))

      # Test the VCL of the previous version
      @requests << stub_request(:put, "https://api.fastly.com/service/123321abc/version/2/vcl/test-vcl/main").
        to_return(body: "{}")

      @requests << stub_request(:get, "https://api.fastly.com/service/123321abc/version/2/generated_vcl").
        to_return(body: "{}")

      @requests << stub_request(:get, "https://api.fastly.com/service/123321abc/version/3/generated_vcl").
        to_return(body: "{}")

      # Activate the version we've just created
      @requests << stub_request(:put, "https://api.fastly.com/service/123321abc/version/3/activate").
        to_return(body: "{}")

      ClimateControl.modify APP_DOMAIN: "gov.uk", FASTLY_SERVICE_ID: "123321abc", FASTLY_USER: 'fastly@example.com', FASTLY_PASS: '123' do
        DeployBouncer.new.deploy!

        @requests.each do |request|
          expect(request).to have_been_requested.at_least_once
        end
      end
    end
  end
end

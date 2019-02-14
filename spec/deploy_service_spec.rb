require './lib/deploy_service'

describe DeployService do
  describe '#deploy' do
    it 'deploys the VCL' do
      @requests = []

      # This call is made by the Fastly library when you call `Fastly.new`
      @requests << stub_request(:post, "https://api.fastly.com/login").to_return(body: "{}")

      # Fastly#get_service. Return a service with two VCL "versions" (https://docs.fastly.com/api/config#version)
      @requests << stub_request(:get, "https://api.fastly.com/service/123321abc").
        to_return(body: File.read("spec/fixtures/fastly-get-service-response.json"))

      # We clone the latest active VCL version, which returns the latest version
      @requests << stub_request(:put, "https://api.fastly.com/service/123321abc/version/2/clone").
        to_return(body: File.read("spec/fixtures/fastly-put-clone.json"))

      # Stub calls to delete the "UI objects"
      %w[backend healthcheck cache_settings request_settings response_object header gzip].each do |thing|
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

      # Get the settings
      @requests << stub_request(:get, "https://api.fastly.com/service/123321abc/version/3/settings").
        to_return(body: File.read("spec/fixtures/fastly-get-settings.json"))

      # And update them
      @requests << stub_request(:put, "https://api.fastly.com/service/123321abc/version/3/settings").
        to_return(body: "{}")

      # Check that the new config is good
      @requests << stub_request(:get, "https://api.fastly.com/service/123321abc/version/3/validate").
        to_return(body: JSON.dump(status: "ok"))

      # Activate the version we've just created
      @requests << stub_request(:put, "https://api.fastly.com/service/123321abc/version/3/activate").
        to_return(body: "{}")

      deployer = DeployService.new

      ClimateControl.modify FASTLY_USER: 'fastly@example.com', FASTLY_PASS: '123' do
        deployer.deploy!(%w[test production])

        @requests.each do |request|
          expect(request).to have_been_requested.at_least_once
        end
      end
    end
  end
end

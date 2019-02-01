describe DeployDictionaries do
  describe '#deploy' do
    it 'deploys the dictionaries to Fastly' do
      # This call is made by the Fastly library when you call `Fastly.new`
      stub_request(:post, "https://api.fastly.com/login").to_return(body: "{}")

      # Fastly#get_service. Return a service with two VCL "versions" (https://docs.fastly.com/api/config#version)
      stub_request(:get, "https://api.fastly.com/service/123321abc").
        to_return(body: File.read("spec/fixtures/fastly-get-service-response.json"))

      # We clone the latest active VCL version, which returns the latest version
      stub_request(:put, "https://api.fastly.com/service/123321abc/version/2/clone").
        to_return(body: File.read("spec/fixtures/fastly-put-clone.json"))

      # Check if the dictionary exists
      stub_request(:get, "https://api.fastly.com/service/123321abc/version/3/dictionary").
        to_return(body: "{}")

      # It doesn't, so create the dictionary
      stub_request(:post, "https://api.fastly.com/service/123321abc/version/3/dictionary").
        to_return(body: "{}")

      # Activate the version we've just created
      stub_request(:put, "https://api.fastly.com/service/123321abc/version/3/activate").
        to_return(body: "{}")

      ClimateControl.modify SERVICE_NAME: "test", ENVIRONMENT: "production", FASTLY_USER: 'fastly@example.com', FASTLY_PASS: '123' do
        DeployDictionaries.new.deploy!
      end
    end
  end
end

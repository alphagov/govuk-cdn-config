describe DeployService do
  describe "#deploy" do
    let(:service_id) { "123321abc" }
    let(:service_types) { %w[healthcheck cache_settings request_settings response_object header gzip] }

    it "deploys the VCL" do
      @requests = stub_fastly_get_service(service_id)
      @requests += stub_fastly_delete_old_vcl(service_id, service_types)
      @requests += stub_fastly_upload_new_vcl(service_id)

      # Get the settings
      @requests << stub_request(:get, "https://api.fastly.com/service/#{service_id}/version/3/settings")
        .to_return(body: File.read("spec/fixtures/fastly-get-settings.json"))

      # And update them
      @requests << stub_request(:put, "https://api.fastly.com/service/#{service_id}/version/3/settings")
        .to_return(body: "{}")

      # Check that the new config is good
      @requests << stub_request(:get, "https://api.fastly.com/service/#{service_id}/version/3/validate")
        .to_return(body: JSON.dump(status: "ok"))

      @requests << stub_fastly_activate_new_vcl(service_id)

      ClimateControl.modify FASTLY_API_KEY: "fastly@example.com" do
        DeployService.new.deploy!(%w[test production])

        expect(@requests).to all(have_been_requested.at_least_once)
      end
    end

    it "raises error when vhost or environment is missing" do
      ClimateControl.modify FASTLY_API_KEY: "fastly@example.com" do
        expect { DeployService.new.deploy!(%w[test]) }
        .to raise_error(RuntimeError, /Usage: #{$PROGRAM_NAME} <configuration> <environment>/)
      end
    end

    it "raises error when vhost and environment combination is not in fastly.yaml" do
      ClimateControl.modify FASTLY_API_KEY: "fastly@example.com" do
        expect { DeployService.new.deploy!(%w[test staging]) }
        .to raise_error(RuntimeError, /Error: Unknown configuration\/environment combination: test staging. Check this combination exists in fastly.yaml./)
      end
    end

    it "fails when delete ui objects fails" do
      @requests = stub_fastly_get_service(service_id)
      @requests += stub_fastly_unsuccessfully_delete_old_vcl(service_id, "healthcheck")

      ClimateControl.modify FASTLY_API_KEY: "fastly@example.com" do
        expect { DeployService.new.deploy!(%w[test production]) }
        .to raise_error(RuntimeError, /Error: Failed to delete configuration/)

        expect(@requests).to all(have_been_requested.at_least_once)
      end
    end

    it "fails when there are no active versions of the configuration" do
      @requests = []

      # Fastly#get_service. Return a service with two VCL "versions" (https://docs.fastly.com/api/config#version)
      @requests << stub_request(:get, "https://api.fastly.com/service/#{service_id}")
      .to_return(body: File.read("spec/fixtures/fastly-get-service-response-inactive-versions.json"))

      @requests += stub_fastly_delete_old_vcl(service_id, service_types)

      # We first check the latest version
      @requests << stub_request(:get, "https://api.fastly.com/service/#{service_id}/version/3/vcl/main")
      .to_return(body: "{}")

      # We then delete it
      @requests << stub_request(:delete, "https://api.fastly.com/service/#{service_id}/version/3/vcl/main")
        .to_return(body: "{}")

      # Then send the actual VCL
      # https://docs.fastly.com/api/config#vcl_7ade6ab5926b903b6acf3335a85060cc
      @requests << stub_request(:post, "https://api.fastly.com/service/#{service_id}/version/3/vcl")
        .to_return(body: File.read("spec/fixtures/fastly-post-vcl.json"))

      # Test the VCL of the previous version
      @requests << stub_request(:put, "https://api.fastly.com/service/#{service_id}/version/2/vcl/test-vcl/main")
        .to_return(body: "{}")

      ClimateControl.modify FASTLY_API_KEY: "fastly@example.com" do
        expect { DeployService.new.deploy!(%w[test production]) }
        .to raise_error(RuntimeError, /There are no active versions of this configuration/)

        expect(@requests).to all(have_been_requested.at_least_once)
      end
    end

    it "fails when the new configuration is invalid" do
      @requests = stub_fastly_get_service(service_id)
      @requests += stub_fastly_delete_old_vcl(service_id, service_types)
      @requests += stub_fastly_upload_new_vcl(service_id)

      # Get the settings
      @requests << stub_request(:get, "https://api.fastly.com/service/#{service_id}/version/3/settings")
        .to_return(body: File.read("spec/fixtures/fastly-get-settings.json"))

      # And update them
      @requests << stub_request(:put, "https://api.fastly.com/service/#{service_id}/version/3/settings")
        .to_return(body: "{}")

      # Check that the new config is valid
      @requests << stub_request(:get, "https://api.fastly.com/service/#{service_id}/version/3/validate")
        .to_return(body: JSON.dump(status: 500, msg: "Error message"))

      ClimateControl.modify FASTLY_API_KEY: "fastly@example.com" do
        expect { DeployService.new.deploy!(%w[test production]) }
        .to raise_error(RuntimeError, /Error: Invalid configuration:\n Error message/)

        expect(@requests).to all(have_been_requested.at_least_once)
      end
    end
  end
end

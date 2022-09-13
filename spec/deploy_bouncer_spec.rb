describe DeployBouncer do
  describe "#deploy" do
    let(:service_id) { "123321abc" }
    let(:service_types) { %w[backend healthcheck condition request_settings cache_settings response_object header gzip] }

    it "deploys the VCL for bouncer" do
      @requests = stub_fastly_get_service(service_id)
      @requests += stub_fastly_delete_old_vcl(service_id, service_types)
      @requests += stub_fastly_upload_new_vcl(service_id)
      @requests += stub_fastly_handle_transition_hosts(service_id)
      @requests << stub_fastly_activate_new_vcl(service_id)

      ClimateControl.modify APP_DOMAIN: "gov.uk", FASTLY_SERVICE_ID: service_id, FASTLY_API_KEY: "fastly@example.com" do
        DeployBouncer.new.deploy!

        expect(@requests).to all(have_been_requested.at_least_once)
      end
    end

    it "fails when APP_DOMAIN is not set" do
      ClimateControl.modify FASTLY_SERVICE_ID: service_id, FASTLY_API_KEY: "fastly@example.com" do
        expect { DeployBouncer.new.deploy! }
        .to raise_error(SystemExit, /APP_DOMAIN environment variable is not set/)
      end
    end

    it "fails when FASTLY_SERVICE_ID is not set" do
      ClimateControl.modify APP_DOMAIN: "gov.uk", FASTLY_API_KEY: "fastly@example.com" do
        expect { DeployBouncer.new.deploy! }
        .to raise_error(SystemExit, /FASTLY_SERVICE_ID environment variable is not set/)
      end
    end

    it "fails when FASTLY_API_KEY is not set" do
      ClimateControl.modify APP_DOMAIN: "gov.uk", FASTLY_SERVICE_ID: service_id do
        expect { DeployBouncer.new.deploy! }
        .to raise_error(RuntimeError, /FASTLY_API_KEY is not set in the environment/)
      end
    end

    it "fails when no hosts found in Transition hosts API" do
      @requests = stub_fastly_get_service(service_id)

      # Given Transition has no hosts
      @requests << stub_request(:get, "https://transition.publishing.service.gov.uk/hosts.json")
        .to_return(body: JSON.dump(results: []))

      # And Fastly has one host
      @requests << stub_request(:get, "https://api.fastly.com/service/#{service_id}/version/3/domain")
        .to_return(body: JSON.dump([{ name: "existing.example.com" }]))

      ClimateControl.modify APP_DOMAIN: "gov.uk", FASTLY_SERVICE_ID: service_id, FASTLY_API_KEY: "fastly@example.com" do
        expect { DeployBouncer.new.deploy! }
        .to raise_error(RuntimeError, /No hosts found in Transition hosts API/)

        expect(@requests).to all(have_been_requested.at_least_once)
      end
    end

    it "fails when delete ui objects fails" do
      @requests = stub_fastly_get_service(service_id)
      @requests += stub_fastly_handle_transition_hosts(service_id)
      @requests += stub_fastly_unsuccessfully_delete_old_vcl(service_id, "backend")

      ClimateControl.modify APP_DOMAIN: "gov.uk", FASTLY_SERVICE_ID: service_id, FASTLY_API_KEY: "fastly@example.com" do
        expect { DeployBouncer.new.deploy! }
        .to raise_error(RuntimeError, /Error: Failed to delete configuration/)

        expect(@requests).to all(have_been_requested.at_least_once)
      end
    end
  end
end

describe DeployDictionaries do
  describe "#deploy" do
    let(:service_id) { "123321abc" }

    it "deploys the dictionaries" do
      @requests = stub_fastly_get_service(service_id)

      @requests << stub_request(:get, "https://api.fastly.com/service/#{service_id}/version/3/dictionary")
        .to_return do |_request|
          if @deleted
            { body: JSON.dump([{ id: "qwerty", name: "example_percentages", version: 1, service_id: service_id }]) }
          else
            @deleted = true
            { body: JSON.dump([{ id: "qwerty", name: "example_percentages", version: 1, service_id: service_id }, { name: "to_be_deleted_because_theres_no_yaml_file", version: 1, service_id: service_id }]) }
          end
        end

      @requests << stub_request(:delete, "https://api.fastly.com/service/#{service_id}/version/1/dictionary/to_be_deleted_because_theres_no_yaml_file")
        .to_return(body: "{}")

      @requests << stub_request(:post, "https://api.fastly.com/service/#{service_id}/version/3/dictionary")
        .to_return(body: "{}")

      @requests << stub_request(:get, "https://api.fastly.com/service/#{service_id}/dictionary/qwerty/items")
          .to_return(body: "{}")

      @requests << stub_request(:post, "https://api.fastly.com/service/#{service_id}/dictionary/qwerty/item")
        .with(
          body: { "dictionary_id" => "qwerty", "item_key" => "A", "item_value" => "50", "service_id" => service_id },
        )
        .to_return(body: "{}")

      @requests << stub_request(:post, "https://api.fastly.com/service/#{service_id}/dictionary/qwerty/item")
        .with(
          body: { "dictionary_id" => "qwerty", "item_key" => "B", "item_value" => "50", "service_id" => service_id },
        )
        .to_return(body: "{}")

      @requests << stub_request(:put, "https://api.fastly.com/service/#{service_id}/version/3/activate")
          .to_return(body: "{}")

      ClimateControl.modify FASTLY_API_KEY: "fastly@example.com" do
        DeployDictionaries.new.deploy!(%w[test production])

        expect(@requests).to all(have_been_requested.at_least_once)
      end
    end

    it "raises error when vhost or environment is missing" do
      ClimateControl.modify FASTLY_API_KEY: "fastly@example.com" do
        expect { DeployDictionaries.new.deploy!(%w[test]) }
        .to raise_error(RuntimeError, /Usage: #{$PROGRAM_NAME} <vhost> <environment>/)
      end
    end

    it "raises error when vhost and environment combination is not in fastly.yaml" do
      ClimateControl.modify FASTLY_API_KEY: "fastly@example.com" do
        expect { DeployDictionaries.new.deploy!(%w[test staging]) }
        .to raise_error(RuntimeError, /Unknown vhost\/environment combination: test staging/)
      end
    end
  end
end

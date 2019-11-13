describe DeployDictionaries do
  describe "#deploy" do
    it "deploys the dictionaries" do
      @requests = []

      # Fastly#get_service. Return a service with two VCL "versions" (https://docs.fastly.com/api/config#version)
      @requests << stub_request(:get, "https://api.fastly.com/service/123321abc").
        to_return(body: File.read("spec/fixtures/fastly-get-service-response.json"))

      # We clone the latest active VCL version, which returns the latest version
      @requests << stub_request(:put, "https://api.fastly.com/service/123321abc/version/2/clone").
        to_return(body: File.read("spec/fixtures/fastly-put-clone.json"))

      @requests << stub_request(:get, "https://api.fastly.com/service/123321abc/version/3/dictionary").
        to_return { |_request|
          if @deleted
            { body: JSON.dump([{ id: "qwerty", name: "example_percentages", version: 1, service_id: "123321abc" }]) }
          else
            @deleted = true
            { body: JSON.dump([{ id: "qwerty", name: "example_percentages", version: 1, service_id: "123321abc" }, { name: "to_be_deleted_because_theres_no_yaml_file", version: 1, service_id: "123321abc" }]) }
          end
        }

      @requests << stub_request(:delete, "https://api.fastly.com/service/123321abc/version/1/dictionary/to_be_deleted_because_theres_no_yaml_file").
        to_return(body: "{}")

      @requests << stub_request(:post, "https://api.fastly.com/service/123321abc/version/3/dictionary").
        to_return(body: "{}")

      @requests << stub_request(:get, "https://api.fastly.com/service/123321abc/dictionary/qwerty/items").
          to_return(body: "{}")

      @requests << stub_request(:post, "https://api.fastly.com/service/123321abc/dictionary/qwerty/item").
        with(
          body: { "dictionary_id" => "qwerty", "item_key" => "A", "item_value" => "50", "service_id" => "123321abc" },
        ).
        to_return(body: "{}")

      @requests << stub_request(:post, "https://api.fastly.com/service/123321abc/dictionary/qwerty/item").
        with(
          body: { "dictionary_id" => "qwerty", "item_key" => "B", "item_value" => "50", "service_id" => "123321abc" },
        ).
        to_return(body: "{}")

      @requests << stub_request(:put, "https://api.fastly.com/service/123321abc/version/3/activate").
          to_return(body: "{}")

      ClimateControl.modify FASTLY_API_KEY: "fastly@example.com" do
        DeployDictionaries.new.deploy!(%w[test production])

        @requests.each do |request|
          expect(request).to have_been_requested.at_least_once
        end
      end
    end
  end
end

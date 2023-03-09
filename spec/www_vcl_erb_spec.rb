def cwd
  File.dirname(__FILE__)
end

RSpec.describe "VCL template" do
  # `ab_tests`, `config` and `environment` are binding vars needed by the www.vcl.erb template
  let!(:config) do
    {
      "origin_hostname" => "foo",
      "service_id" => "123",
      "provider1_mirror_hostname" => "foo",
      "s3_mirror_hostname" => "bar",
      "s3_mirror_prefix" => "foo_",
      "default_ttl" => "5000",
      "probe" => "/",
    }
  end
  let!(:environment) { "test" }
  let!(:ab_tests) { [{ "ATest" => %w[meh boom] }, { "Example" => %w[A B] }] }

  subject(:rendered) do
    RenderTemplate.call("www", locals: { config:, environment:, ab_tests: })
  end

  it "renders the AB tests partial" do
    expect(rendered).to include(%(set req.http.GOVUK-ABTest-ATest = \"meh\";))
  end

  it "renders the expiry statements" do
    statement = %(set var.expiry = time.add(now, std.integer2time(std.atoi(table.lookup(ab_test_expiries, "ATest"))));)
    expect(rendered).to include(statement)
  end

  it "doesn't set a cookie for the 'Example' test" do
    expect(rendered).not_to include(%(add resp.http.Set-Cookie = "ABTest-<%= test %>=))
  end
end

describe "Expected AB test files" do
  let(:expiries) { YAML.load_file(File.join(cwd, "../configs/dictionaries/ab_test_expiries.yaml")) }
  let(:active_tests) { YAML.load_file(File.join(cwd, "../configs/dictionaries/active_ab_tests.yaml")) }

  configured_tests = YAML.load_file(File.join(cwd, "../ab_tests/ab_tests.yaml")).map(&:keys).flatten

  configured_tests.each do |test_name|
    it "includes #{test_name}'s percentage file" do
      percentage_file = File.join(cwd, "../configs/dictionaries/#{test_name.downcase}_percentages.yaml")
      expect(File.exist?(percentage_file)).to be true
    end

    it "includes #{test_name}'s expiry time config" do
      expect(expiries).to have_key(test_name)
    end

    it "includes #{test_name}'s active state config" do
      expect(expiries).to have_key(test_name)
    end
  end
end

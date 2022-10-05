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
    RenderTemplate.call("www", locals: { config: config, environment: environment, ab_tests: ab_tests })
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

describe "AB Tests partial" do
  let(:expected) do
    @expected ||= File.new(File.join(cwd, "fixtures/_multivariate_tests.vcl.erb.out")).read
  end

  let!(:ab_tests) do
    [
      { "MyTest" => %w[foo bar] },
      { "YourTest" => %w[variant1 variant2 variant3 variant4] },
    ]
  end

  subject do
    partial_path = File.join(cwd, "../vcl_templates/_multivariate_tests.vcl.erb")
    @rendered ||= ERB.new(File.new(partial_path).read, trim_mode: "-").result(binding)
  end

  it "renders ab test output for each test in the configuration" do
    expect(subject).to eq(expected)
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

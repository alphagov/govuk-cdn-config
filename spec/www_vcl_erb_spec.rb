require 'erb'
require "rspec"

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
    }
  end
  let!(:environment) { "test" }
  let!(:ab_tests) { [{ "ATest" => %w(meh boom) }] }

	let(:expected) do
    @expected_vcl ||= File.new(File.join(cwd, "fixtures/www.vcl.erb.out")).read
  end
  subject do
    template_path = File.join(cwd, "../vcl_templates/www.vcl.erb")
    @rendered_vcl ||= ERB.new(File.new(template_path).read, nil, "-", "_test_erbout").result(binding)
  end

  it "renders the AB tests partial" do
    expect(subject).to include(%Q(set req.http.GOVUK-ABTest-ATest = \"meh\";))
  end

  it "renders the expiry statements" do
    statement = %Q(set var.expiry = time.add(now, std.integer2time(std.atoi(table.lookup(ab_test_expiries, "ATest"))));)
    expect(subject).to include(statement)
  end

  it "renders the formatted vcl" do
    expect(subject).to eq(expected)
  end
end

describe "AB Tests partial" do
  let(:expected) do
		@expected ||= File.new(File.join(cwd, "fixtures/_ab_tests.erb.out")).read
  end

  let(:partial_path) do
    File.join(cwd, "../vcl_templates/_ab_tests.erb")
  end

  let!(:ab_tests) do
    [
      { "MyTest" => %w(foo bar) },
      { "YourTest" => %w(variant1 variant2 variant3 variant4)}
    ]
  end

  subject do
    @rendered ||= ERB.new(File.new(partial_path).read, nil, "-").result(binding)
  end

  it "renders ab test output for each test in the configuration" do
    expect(subject).to eq(expected)
  end
end

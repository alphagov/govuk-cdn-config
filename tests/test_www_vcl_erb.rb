require 'erb'
require "minitest/spec"
require "minitest/autorun"

def cwd
  File.dirname(__FILE__)
end

describe "VCL template" do
  before do
    # `ab_tests`, `config` and `environment` are binding vars needed by the www.vcl.erb template
    config = {
      "origin_hostname" => "foo",
      "service_id" => "123",
      "provider1_mirror_hostname" => "foo",
      "s3_mirror_hostname" => "bar",
      "s3_mirror_prefix" => "foo_",
      "default_ttl" => "5000",
    }
    environment = "test"
    ab_tests = [{ "ATest" => %w(meh boom) }]

    template_path = File.join(cwd, "../vcl_templates/www.vcl.erb")
		@expected_vcl ||= File.new(File.join(cwd, "fixtures/www.vcl.erb.out")).read
    @rendered_vcl ||= ERB.new(File.new(template_path).read, nil, "-", "_test_erbout").result(binding)
  end

  it "renders the AB tests partial" do
    assert_includes(@rendered_vcl, %Q(set req.http.GOVUK-ABTest-ATest = \"meh\";))
  end

  it "renders the expiry statements" do
    statement = %Q(set var.expiry = time.add(now, std.integer2time(std.atoi(table.lookup(ab_test_expiries, "ATest"))));)
    assert_includes(@rendered_vcl, statement)
  end

  it "renders the formatted vcl" do
    assert_equal(@expected_vcl, @rendered_vcl)
  end
end

describe "AB Tests partial" do
  before do
    partial_path = File.join(cwd, "../vcl_templates/_ab_tests.erb")
    ab_tests = [
      { "MyTest" => %w(foo bar) },
      { "YourTest" => %w(variant1 variant2 variant3 variant4)}
    ]
		@expected ||= File.new(File.join(cwd, "fixtures/_ab_tests.erb.out")).read
    @rendered ||= ERB.new(File.new(partial_path).read, nil, "-").result(binding)
  end

  it "renders ab test output for each test in the configuration" do
    assert_equal(@expected, @rendered)
  end
end

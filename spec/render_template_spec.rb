RSpec.describe RenderTemplate do
  describe ".call" do
    it "renders the ERB template" do
      allow(File)
        .to receive(:read)
        .with(/test.vcl.erb\z/)
        .and_return("<%= my_var %>\n")

      result = described_class.call("test", locals: { my_var: "foobar" })

      expect(result).to eql("foobar\n")
    end
  end
end

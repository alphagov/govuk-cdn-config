RSpec.describe RenderTemplate do
  describe ".call" do
    it "renders the ERB template" do
      allow(File)
        .to receive(:read)
        .with(/template.vcl.erb\z/)
        .and_return("<%= my_var %>\n")

      result = described_class.call("template", locals: { my_var: "foobar" })

      expect(result).to eql("foobar\n")
    end
  end

  describe "#render_partial" do
    it "can render a partial" do
      allow(File)
        .to receive(:read)
        .with(/template.vcl.erb\z/)
        .and_return("<%= render_partial('partial', locals: { my_var: 'foobar' }) %>\n")

      allow(File)
        .to receive(:read)
        .with(/_partial.vcl.erb\z/)
        .and_return("<%= my_var -%>\n")

      result = described_class.call("template")

      expect(result).to eql("foobar\n")
    end

    it "can indent partial output" do
      allow(File)
        .to receive(:read)
        .with(/template.vcl.erb\z/)
        .and_return("{\n<%= render_partial('partial', indentation: '  ') %>\n}\n")

      allow(File)
        .to receive(:read)
        .with(/_partial.vcl.erb\z/)
        .and_return("line-1\nline-2\n\nline-3")

      result = described_class.call("template", locals: { my_var: "foobar" })

      expect(result).to eql <<~HEREDOC
        {
          line-1
          line-2

          line-3
        }
      HEREDOC
    end
  end
end

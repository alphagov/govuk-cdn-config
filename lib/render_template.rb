class RenderTemplate
  attr_reader :template, :locals

  def self.call(...)
    new(...).call
  end

  def initialize(template, locals: {})
    @template = template
    @locals = locals
  end

  def call
    embedded_ruby = File.read("#{__dir__}/../vcl_templates/#{template}.vcl.erb")
    ERB.new(embedded_ruby, trim_mode: "-")
       .result(binding_with_local_variables(locals))
  end

  def render_partial(partial, indentation: "", locals: {})
    embedded_ruby = File.read("#{__dir__}/../vcl_templates/_#{partial}.vcl.erb")
    # this is a variable name that ERB sets it output too, we need to set this
    # to be distinct from other renderings that are progressing
    erb_output_var = "_#{partial}_eoutvar"

    output = ERB
      .new(embedded_ruby, trim_mode: "-", eoutvar: erb_output_var)
      .result(binding_with_local_variables(locals))

    if indentation != ""
      output
        .split("\n")
        .map { |line| line.length.positive? ? "#{indentation}#{line}" : line }
        .join("\n")
    else
      output
    end
  end

private

  def binding_with_local_variables(variables)
    binding.tap do |bind|
      variables.each { |k, v| bind.local_variable_set(k, v) }
    end
  end
end

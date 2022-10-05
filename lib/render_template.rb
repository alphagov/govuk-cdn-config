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
    bind = binding
    locals.each { |k, v| bind.local_variable_set(k, v) }

    embedded_ruby = File.read("#{__dir__}/../vcl_templates/#{template}.vcl.erb")
    ERB.new(embedded_ruby, trim_mode: "-").result(bind)
  end
end

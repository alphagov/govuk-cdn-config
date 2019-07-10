class GovukFastly
  def self.client
    Fastly.new(api_key: ENV.fetch("FASTLY_API_KEY"))
  rescue KeyError
    raise "FASTLY_API_KEY is not set in the environment"
  end
end

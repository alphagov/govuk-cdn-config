class GovukFastly
  def self.client
    %w[FASTLY_USER FASTLY_PASS].each do |envvar|
      if ENV[envvar].nil?
        raise "#{envvar} is not set in the environment"
      end
    end

    Fastly.new(
      user: ENV['FASTLY_USER'],
      password: ENV['FASTLY_PASS']
    )
  end

  # The deploy bouncer job uses a different client. This should be refactored
  # to use `GovukFastly.client`
  def self.weird_legacy_client
    Fastly::Client.new(
      user: ENV['FASTLY_USER'],
      password: ENV['FASTLY_PASS']
    )
  end
end

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
end

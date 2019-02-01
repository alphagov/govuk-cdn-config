class DeployService
  CONFIGS = YAML.load_file(File.join(__dir__, "..", "fastly.yaml"))

  def deploy!
    service_name = ENV.fetch("SERVICE_NAME")
    environment = ENV.fetch("ENVIRONMENT")

    change = FastlyChange.new(service_id: config["service_id"])

    version = change.development_version

    puts "Current version: #{version.number}"
    puts "Configuration: #{service_name}"
    puts "Environment: #{environment}"

    config['git_version'] = get_git_version

    vcl = RenderTemplate.render_template(service_name, environment, config)
    change.delete_ui_objects!
    change.upload_vcl!(vcl)
    change.output_vcl_diff

    modify_settings!(version, config['default_ttl'])

    change.activate!
  end

private

  def config
    @config ||= begin
      service_name = ENV.fetch("SERVICE_NAME")
      environment = ENV.fetch("ENVIRONMENT")
      CONFIGS[service_name][environment] || raise("Unknown service/environment combination")
    end
  end

  def get_git_version
    ref = %x{git describe --always}.chomp
    ref = "unknown" if ref.empty?

    ref
  end

  def modify_settings!(version, ttl)
    settings = version.settings
    settings.settings.update(
      "general.default_host" => "",
      "general.default_ttl"  => ttl,
    )
    settings.save!
  end
end

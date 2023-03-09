class DeployService < DeployBase
  CONFIGS = YAML.load_file(File.join(__dir__, "..", "fastly.yaml"))

  def deploy!(argv)
    configuration, environment, config = get_config(argv)

    @fastly = GovukFastly.client
    config["git_version"] = get_git_version

    service = @fastly.get_service(config["service_id"])
    version = get_dev_version(service)
    puts "Current version: #{version.number}"
    puts "Configuration: #{configuration}"
    puts "Environment: #{environment}"

    vcl = RenderTemplate.call(
      configuration,
      locals: {
        configuration:,
        environment:,
        config:,
        version:,
        ab_tests: ab_tests_config,
      },
    )

    dry_run = ENV.fetch("FASTLY_DRY_RUN", "").downcase
    unless ["", "0", "false"].include?(dry_run)
      puts vcl
      exit
    end

    service_types = %w[healthcheck cache_settings request_settings response_object header gzip]
    delete_ui_objects(service.id, version.number, service_types)
    upload_vcl(version, vcl)
    diff_vcl(service, version)

    modify_settings(version, config["default_ttl"])

    validate_config(version)
    version.activate!
  end

private

  def ab_tests_config
    @ab_tests_config ||= YAML.load_file(File.join(__dir__, "..", "ab_tests", "ab_tests.yaml"))
  end

  def get_config(args)
    raise "Usage: #{$PROGRAM_NAME} <configuration> <environment>" unless args.size == 2

    configuration = args[0]
    environment = args[1]
    config_hash = begin
      CONFIGS[configuration][environment]
    rescue StandardError
      nil
    end

    raise "Error: Unknown configuration/environment combination: #{configuration} #{environment}. Check this combination exists in fastly.yaml." unless config_hash

    [configuration, environment, config_hash]
  end

  def get_git_version
    ref = `git describe --always`.chomp
    ref = "unknown" if ref.empty?

    ref
  end

  def modify_settings(version, ttl)
    settings = version.settings
    settings.settings.update(
      "general.default_host" => "",
      "general.default_ttl" => ttl,
    )
    settings.save!
  end

  def validate_config(version)
    is_valid_vcl, error_message = version.validate

    unless is_valid_vcl
      raise "Error: Invalid configuration:\n #{error_message}"
    end
  end
end

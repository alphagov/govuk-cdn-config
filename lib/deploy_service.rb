class DeployService
  CONFIGS = YAML.load_file(File.join(__dir__, "..", "fastly.yaml"))

  def deploy!
    service_name = ENV.fetch("SERVICE_NAME")
    environment = ENV.fetch("ENVIRONMENT")

    change = FastlyChange.new(service_id: config["service_id"])

    @fastly = FastlyClient.client
    service = change.service

    version = change.development_version

    config['git_version'] = get_git_version

    puts "Current version: #{version.number}"
    puts "Configuration: #{service_name}"
    puts "Environment: #{environment}"

    vcl = RenderTemplate.render_template(service_name, environment, config)
    delete_ui_objects(service.id, version.number)
    change.upload_vcl!(vcl)
    change.output_vcl_diff

    modify_settings(version, config['default_ttl'])

    validate_config(version)
    version.activate!
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

  def delete_ui_objects(service_id, version_number)
    # Delete objects created by the UI. We want VCL to be the source of truth.
    # Most of these don't have real objects in the Fastly API gem.
    to_delete = %w{backend healthcheck cache_settings request_settings response_object header gzip}
    to_delete.each do |type|
      type_path = "/service/#{service_id}/version/#{version_number}/#{type}"
      @fastly.client.get(type_path).map { |i| i["name"] }.each do |name|
        puts "Deleting #{type}: #{name}"
        resp = @fastly.client.delete("#{type_path}/#{ERB::Util.url_encode(name)}")
        raise 'ERROR: Failed to delete configuration' unless resp
      end
    end
  end

  def modify_settings(version, ttl)
    settings = version.settings
    settings.settings.update(
      "general.default_host" => "",
      "general.default_ttl"  => ttl,
    )
    settings.save!
  end

  def validate_config(version)
    unless version.validate
      raise "ERROR: Invalid configuration:\n" + valid_hash.fetch('msg')
    end
  end
end

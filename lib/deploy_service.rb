class DeployService
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

    vcl = RenderTemplate.render_template(configuration, environment, config, version)

    dry_run = ENV.fetch("FASTLY_DRY_RUN", "").downcase
    unless ["", "0", "false"].include?(dry_run)
      puts vcl
      exit
    end

    delete_ui_objects(service.id, version.number)
    upload_vcl(version, vcl)
    diff_vcl(service, version)

    modify_settings(version, config["default_ttl"])

    validate_config(version)
    version.activate!
  end

private

  def get_config(args)
    raise "Usage: #{$PROGRAM_NAME} <configuration> <environment>" unless args.size == 2

    configuration = args[0]
    environment = args[1]
    config_hash = begin
                    CONFIGS[configuration][environment]
                  rescue StandardError
                    nil
                  end

    raise "ERROR: Unknown configuration/environment combination. Check this combination exists in fastly.yaml." unless config_hash

    [configuration, environment, config_hash]
  end

  def get_git_version
    ref = `git describe --always`.chomp
    ref = "unknown" if ref.empty?

    ref
  end

  def get_dev_version(configuration)
    # Sometimes the latest version isn't the development version.
    version = configuration.version
    version = version.clone if version.active?

    version
  end

  def delete_ui_objects(service_id, version_number)
    # Delete objects created by the UI. We want VCL to be the source of truth.
    # Most of these don't have real objects in the Fastly API gem.
    to_delete = %w[healthcheck cache_settings request_settings response_object header gzip]
    to_delete.each do |type|
      type_path = "/service/#{service_id}/version/#{version_number}/#{type}"
      @fastly.client.get(type_path).map { |i| i["name"] }.each do |name|
        puts "Deleting #{type}: #{name}"
        resp = @fastly.client.delete("#{type_path}/#{ERB::Util.url_encode(name)}")
        raise "ERROR: Failed to delete configuration" unless resp
      end
    end
  end

  def modify_settings(version, ttl)
    settings = version.settings
    settings.settings.update(
      "general.default_host" => "",
      "general.default_ttl" => ttl,
    )
    settings.save!
  end

  def upload_vcl(version, contents)
    vcl_name = "main"

    begin
      version.vcl(vcl_name) && version.delete_vcl(vcl_name)
    rescue Fastly::Error => e
      puts "Error: #{e.inspect}"
    end

    vcl = version.upload_vcl(vcl_name, contents)
    @fastly.client.put(Fastly::VCL.put_path(vcl) + "/main")
  end

  def diff_vcl(configuration, version_new)
    version_current = configuration.versions.find(&:active?)

    if version_current.nil?
      raise "There are no active versions of this configuration"
    end

    diff = Diffy::Diff.new(
      version_current.generated_vcl.content,
      version_new.generated_vcl.content,
      context: 3,
    )

    puts "Diff versions: #{version_current.number} -> #{version_new.number}"
    puts diff.to_s(:color)
  end

  def validate_config(version)
    is_valid_vcl, error_message = version.validate

    unless is_valid_vcl
      raise "ERROR: Invalid configuration:\n #{error_message}"
    end
  end
end

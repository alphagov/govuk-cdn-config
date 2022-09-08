class DeployBase
  def get_dev_version(configuration)
    # Sometimes the latest version isn't the development version.
    version = configuration.version
    version = version.clone if version.active?

    version
  end

  def delete_ui_objects(service_id, version_number, service_types)
    # Delete objects created by the UI. We want VCL to be the source of truth.
    # Most of these don't have real objects in the Fastly API gem.
    service_types.each do |type|
      type_path = "/service/#{service_id}/version/#{version_number}/#{type}"
      @fastly.client.get(type_path).map { |i| i["name"] }.each do |name|
        puts "Deleting #{type}: #{name}"
        resp = @fastly.client.delete("#{type_path}/#{ERB::Util.url_encode(name)}")
        raise "Error: Failed to delete configuration" unless resp
      end
    end
  end

  def upload_vcl(version, contents)
    vcl_name = "main"

    begin
      # It first checks the latest version and then deletes it
      version.vcl(vcl_name) && version.delete_vcl(vcl_name)
    rescue Fastly::Error => e
      puts "Error: #{e.inspect}"
    end

    # Upload the new configuration file
    vcl = version.upload_vcl(vcl_name, contents)
    # Set the new VCL as the service's main one
    @fastly.client.put("#{Fastly::VCL.put_path(vcl)}/main")
  end

  def diff_vcl(configuration, version_new)
    # Display in the task's output the changes that will be applied
    # to the configuration. This is needed for checking that
    # everything is modified as expected.
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
end

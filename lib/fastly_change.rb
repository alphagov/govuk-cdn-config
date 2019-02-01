class FastlyChange
  attr_reader :service_id

  def initialize(service_id:)
    @service_id = service_id
    @fastly = FastlyClient.client
  end

  def service
    @service ||= @fastly.get_service(service_id)
  end

  def development_version
    # Sometimes the latest version isn't the development version.
    version = service.version
    version = version.clone if version.active?
    version
  end

  def upload_vcl!(contents)
    vcl_name = 'main'

    begin
      development_version.vcl(vcl_name) && development_version.delete_vcl(vcl_name)
    rescue Fastly::Error => e
      puts e.inspect
    end

    vcl = development_version.upload_vcl(vcl_name, contents)
    @fastly.client.put(Fastly::VCL.put_path(vcl) + '/main')
  end

  def output_vcl_diff
    version_current = service.versions.find(&:active?)

    if version_current.nil?
      raise 'There are no active versions of this configuration'
    end

    diff = Diffy::Diff.new(
      version_current.generated_vcl.content,
      development_version.generated_vcl.content,
      context: 3
    )

    puts "Diff versions: #{version_current.number} -> #{development_version.number}"
    puts diff.to_s(:color)

    diff
  end
end

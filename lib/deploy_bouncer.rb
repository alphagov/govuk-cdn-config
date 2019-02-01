class DeployBouncer
  def deploy!
    if ENV['APP_DOMAIN']
      app_domain = ENV['APP_DOMAIN']
    else
      abort("APP_DOMAIN environment variable is not set")
    end

    if ENV["FASTLY_USER"]
      user = ENV["FASTLY_USER"]
    else
      abort("FASTLY_USER environment variable is not set")
    end

    if ENV["FASTLY_PASS"]
      password = ENV["FASTLY_PASS"]
    else
      abort("FASTLY_PASS environment variable is not set")
    end

    if ENV["FASTLY_SERVICE_ID"]
      service_id = ENV["FASTLY_SERVICE_ID"]
    else
      abort("FASTLY_SERVICE_ID environment variable is not set")
    end

    if ENV["FASTLY_DRY_RUN"]
      puts "Starting dry run..."
      dry_run = true
    else
      dry_run = false
    end

    # A comma-separated list of hostnames will override the JSON output from Transition
    hostnames = []
    if ENV['HOSTNAMES']
      hostnames = ENV['HOSTNAMES'].split(',')
    end

    @f = Fastly.new(user: user, password: password)
    service = @f.get_service(service_id)

    version = get_dev_version(service)

    hosts_api_results = get_hosts(hostnames)

    existing_domains = get_existing_domains(user, password, service.id, version.number)
    configured_domains = get_configured_domains(hosts_api_results)

    number_of_domains = configured_domains.length
    status_string = "there are #{number_of_domains} domains configured in the Transition app."
    limit_string = 'The limit for the Production Bouncer service (3deosa3b6uKT8IimBYcAv) is 3500.'
    more_info_string = 'See https://fastly.zendesk.com/hc/en-us/requests/7356 for more information.'

    if number_of_domains >= 3500
      puts "Error: #{status_string}".red
      puts limit_string.red
      puts more_info_string.red
      exit 1
    elsif number_of_domains > 3000
      puts "Warning: #{status_string}".blue
      puts limit_string.blue
      puts more_info_string.blue
    end

    # The intersection is the set of elements common to both arrays
    intersection = existing_domains & configured_domains

    # Find out the differences
    extra_existing = existing_domains - intersection
    extra_configured = configured_domains - intersection

    # Test whether we have any changes to make
    if dry_run
      puts "Dry Run complete"

      puts "Here are the domains that would be added:"
      p extra_configured

      puts "Here are the domains that would be removed:"
      p extra_existing
    else
      if extra_existing.any?
        delete_domains(user, password, service.id, version.number, extra_existing)
      end

      if extra_configured.any?
        add_domains(user, password, service.id, version.number, extra_configured)
      end

      vcl = render_vcl(service.id, app_domain)
      delete_ui_objects(service.id, version.number)
      upload_vcl(version, vcl)
      diff = diff_vcl(service, version)

      if (diff.to_s == '') && extra_configured.empty? && extra_existing.empty?
        debug_output("No changes detected; not activating dev version")
      else
        puts "Activating version #{version.number}".blue
        version.activate!
      end
    end
  end

  # The Fastly API has in the past changed the response for `version.active` from
  # string ("1"/"0") to a boolean (true/false). To prevent changing the code when
  # the response changes again, convert any true-like inputs to proper booleans.
  def coerce_boolean(bool_like_thing)
    ['1', true, 'true'].include?(bool_like_thing)
  end

  def debug_output(output)
    if ENV["FASTLY_DEBUG"] == "TRUE"
      puts output.blue
    end
  end

  def get_dev_version(service)
    # Sometimes the latest version isn't the development version.
    version = service.version
    version = version.clone if coerce_boolean(version.active)

    version
  end

  def get_hosts(hostnames)
    if hostnames.empty?
      io = open('https://transition.publishing.service.gov.uk/hosts.json')
      json = JSON.parse(io.read)
      hosts = json['results']
    else
      hosts = hostnames.map { |domain| { 'hostname' => domain } }
    end

    hosts
  end

  def get_configured_domains(hosts_api_results)
    configured_domains = Array.new
    hosts_api_results.each do |host|
      debug_output("Configured domain: #{host['hostname']}")
      configured_domains << host['hostname']
    end
    if configured_domains.compact.empty?
      raise 'No hosts found in Transition hosts API'
    end

    configured_domains.sort
  end

  def get_existing_domains(user, password, service_id, version)
    domains = Array.new
    domain_lister = Fastly::Client.new(user: user, password: password)
    domain_lister.get(Fastly::Domain.list_path(service_id: service_id, version: version)).each do |domain|
      domains.push domain['name']
      debug_output("Existing domain: #{domain['name']}")
    end
    domains.sort
  end

  def delete_domains(user, password, service_id, version, domains)
    deleter = Fastly::Client.new(user: user, password: password)
    domains.each do |domain|
      puts "Deleting #{domain} from the config".yellow
      path = "/service/#{service_id}/version/#{version}/domain/#{domain}"
      deleter.delete(path)
    end
  end

  def add_domains(user, password, service_id, version, domains)
    adder = Fastly.new(user: user, password: password)
    domains.each do |domain|
      begin
        puts "Adding #{domain} to the configuration".green
        adder.create_domain(service_id: service_id, version: version, name: domain, comment: '')
      rescue StandardError
        puts "Cannot add #{domain}, is it owned by another customer?".red
      end
    end
  end

  def render_vcl(service_id, app_domain)
    @app_domain = app_domain

    vcl_file = "vcl_templates/bouncer.vcl.erb"
    vcl_contents = ERB.new(File.read(vcl_file)).result(binding)

    vcl_contents
  end

  def upload_vcl(version, contents)
    vcl_name = 'main'

    begin
      version.vcl(vcl_name) && version.delete_vcl(vcl_name)
    rescue Fastly::Error => e
      puts e.inspect
    end

    vcl = version.upload_vcl(vcl_name, contents)
    @f.client.put(Fastly::VCL.put_path(vcl) + '/main')
  end

  def delete_ui_objects(service_id, version_number)
    # Delete objects created by the UI. We want VCL to be the source of truth.
    # Most of these don't have real objects in the Fastly API gem.
    to_delete = %w{backend healthcheck condition request_settings cache_settings response_object header gzip}
    to_delete.each do |type|
      type_path = "/service/#{service_id}/version/#{version_number}/#{type}"
      @f.client.get(type_path).map { |i| i["name"] }.each do |name|
        puts "Deleting #{type}: #{name}"
        resp = @f.client.delete("#{type_path}/#{ERB::Util.url_encode(name)}")
        raise 'Delete failed' unless resp
      end
    end
  end

  def diff_vcl(service, version_new)
    version_current = service.versions.find { |version| coerce_boolean(version.active) }
    diff = Diffy::Diff.new(
      version_current.generated_vcl.content,
      version_new.generated_vcl.content,
      context: 3
    )

    puts "Diff versions: #{version_current.number} -> #{version_new.number}"
    puts diff.to_s(:color)

    diff
  end
end

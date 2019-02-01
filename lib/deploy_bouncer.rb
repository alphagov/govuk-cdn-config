class DeployBouncer
  def deploy!
    %w[APP_DOMAIN FASTLY_SERVICE_ID].each do |envvar|
      if ENV[envvar].nil?
        raise "#{envvar} is not set in the environment"
      end
    end

    app_domain = ENV['APP_DOMAIN']
    user = ENV["FASTLY_USER"]
    password = ENV["FASTLY_PASS"]
    service_id = ENV["FASTLY_SERVICE_ID"]

    if ENV["FASTLY_DRY_RUN"]
      puts "Starting dry run..."
      dry_run = true
    else
      dry_run = false
    end

    change = FastlyChange.new(service_id: service_id)

    @fastly = FastlyClient.client
    service = change.service

    version = change.development_version

    transitioned_hostnames = TransitionDomains.new.all

    existing_domains = get_existing_domains(user, password, service.id, version.number)

    # The intersection is the set of elements common to both arrays
    intersection = existing_domains & transitioned_hostnames

    # Find out the differences
    extra_existing = existing_domains - intersection
    extra_configured = transitioned_hostnames - intersection

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
        add_domains(service.id, version.number, extra_configured)
      end

      config = {
        "app_domain" => app_domain,
        "service_id" => service_id,
      }

      vcl = RenderTemplate.render_template("bouncer", nil, config)

      delete_ui_objects(service.id, version.number)
      change.upload_vcl!(vcl)
      diff = change.output_vcl_diff

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

  def add_domains(service_id, version, domains)
    domains.each do |domain|
      begin
        puts "Adding #{domain} to the configuration".green
        @fastly.create_domain(service_id: service_id, version: version, name: domain, comment: '')
      rescue StandardError
        puts "Cannot add #{domain}, is it owned by another customer?".red
      end
    end
  end

  def delete_ui_objects(service_id, version_number)
    # Delete objects created by the UI. We want VCL to be the source of truth.
    # Most of these don't have real objects in the Fastly API gem.
    to_delete = %w{backend healthcheck condition request_settings cache_settings response_object header gzip}
    to_delete.each do |type|
      type_path = "/service/#{service_id}/version/#{version_number}/#{type}"
      @fastly.client.get(type_path).map { |i| i["name"] }.each do |name|
        puts "Deleting #{type}: #{name}"
        resp = @fastly.client.delete("#{type_path}/#{ERB::Util.url_encode(name)}")
        raise 'Delete failed' unless resp
      end
    end
  end

  class TransitionDomains
    def all
      number_of_domains = transitioned_hostnames.length
      status_string = "there are #{number_of_domains} domains configured in the Transition app."
      limit_string = "The limit for the `Production Bouncer` service is 3500."
      more_info_string = "See https://fastly.zendesk.com/hc/en-us/requests/7356 for more information"

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

      transitioned_hostnames
    end

    def transitioned_hostnames
      @transitioned_hostnames ||= begin
        io = open('https://transition.publishing.service.gov.uk/hosts.json')
        json = JSON.parse(io.read)
        json['results'].map { |host| host['hostname'] }.sort
      end
    end
  end
end

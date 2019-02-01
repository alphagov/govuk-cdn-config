class DeployDictionaries
  CONFIGS = YAML.load_file("fastly.yaml")

  def deploy!(argv)
    config = get_config(argv)
    username = ENV['FASTLY_USER']
    password = ENV['FASTLY_PASS']

    if username.nil? || password.nil?
      puts "Fastly credentials are not set. Exiting."
      exit 1
    end

    @fastly = Fastly.new(
      user: username,
      password: password,
    )

    service = @fastly.get_service(config['service_id'])

    version = get_dev_version(service)
    puts "Using version #{version.number} of #{service.name}"

    expected_dictionaries = Dir.glob("configs/dictionaries/*.yaml").map { |filename| File.basename(filename, '.yaml') }
    existing_dictionaries = version.dictionaries.map(&:name)

    # Clean up dictionaries which are no longer used
    dictionaries_to_remove = existing_dictionaries - expected_dictionaries

    dictionaries_to_remove.each do |name|
      puts "Deleting existing dictionary '#{name}' from Fastly because it is no longer configured"
      dictionary = version.dictionaries.detect { |d| d.name == name }
      @fastly.delete_dictionary(dictionary)
    end


    dictionaries_to_add = expected_dictionaries - existing_dictionaries

    dictionaries_to_add.each do |name|
      puts "Creating dictionary: #{name}"
      @fastly.create_dictionary(service_id: service.id, version: version.number, name: name)
    end

    version.dictionaries.each do |dictionary|
      expected_items = YAML.load_file("configs/dictionaries/#{dictionary.name}.yaml") || []
      existing_items = dictionary.items

      items_to_add = expected_items.reject { |key, _| existing_items.map(&:item_key).include?(key) }
      items_to_add.each do |key, value|
        puts "Creating dictionary item: #{key} => #{value} in #{dictionary.name}"
        @fastly.create_dictionary_item(service_id: service.id, dictionary_id: dictionary.id, item_key: key, item_value: value)
      end

      items_to_update = existing_items.select { |item| expected_items.include?(item.item_key) }
      items_to_update.each do |item|
        new_value = expected_items[item.item_key]
        if item.item_value != new_value.to_s
          puts "Updating dictionary item #{item.item_key} from '#{item.item_value}' to '#{new_value}' in #{dictionary.name}"
          item.item_value = new_value
          @fastly.update_dictionary_item(item)
        end
      end

      items_to_delete = existing_items.reject { |item| expected_items.include?(item.item_key) }
      items_to_delete.each do |item|
        puts "Deleting dictionary item: #{item.item_key} from #{dictionary.name}"
        @fastly.delete_dictionary_item(item)
      end
    end

    # The cloned version needs to be activated to pick up changes to the dictionaries.
    # This step isn't technically necessary if only the items have been updated, but
    # it's a safe change to make and it's useful to keep a full version history of
    # the Fastly configuratiion.
    version.activate!
  end

  def get_config(args)
    raise "Usage: #{$0} <vhost> <environment>" unless args.size == 2

    vhost = args[0]
    environment = args[1]
    CONFIGS[vhost][environment] || raise("Unknown vhost/environment combination")
  end

  def get_dev_version(service)
    version = service.version
    version = version.clone if version.active?

    version
  end
end

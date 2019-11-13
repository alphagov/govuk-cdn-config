require "colorize"
require "diffy"
require "erb"
require "fastly"
require "open-uri"
require "yaml"

require_relative "./deploy_bouncer"
require_relative "./deploy_dictionaries"
require_relative "./deploy_service"
require_relative "./govuk_fastly"
require_relative "./render_template"

# TODO: Move this into https://github.com/fastly/fastly-ruby
class Fastly
  class Version < Base
    def domains
      fetcher.list_domains(service_id: service_id, version: number)
    end
  end
end

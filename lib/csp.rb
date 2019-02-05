class CSP
  # Generate a Content Security Policy (CSP) directive.
  #
  # Extracted in a separate class to allow comments.
  #
  # See https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP for more CSP info.
  #
  # The resulting policy should be checked with:
  #
  # - https://csp-evaluator.withgoogle.com
  # - https://cspvalidator.org
  def self.generate
    policies = []

    # By default, only allow HTTPS connections, and allow loading things from
    # the publishing domain
    #
    # https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy/default-src
    policies << "default-src https 'self' *.publishing.service.gov.uk"

    # Allow images from the current domain, Google Analytics (the tracking
    # pixel), and publishing domains
    #
    # https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy/img-src
    policies << "img-src 'self' www.google-analytics.com *.publishing.service.gov.uk"

    # script-src determines the scripts that the browser can load
    #
    # https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy/script-src
    policies << [
      # Allow scripts from Google Analytics and publishing domains
      "script-src 'self' www.google-analytics.com *.publishing.service.gov.uk",

      # Allow the script that adds `js-enabled` to the body from govuk_template
      # https://github.com/alphagov/govuk_template/blob/79340eb91ad8c4279d16da302765d0946d89b1ca/source/views/layouts/govuk_template.html.erb#L40
      "'sha256-G29/qSW/JHHANtFhlrZVDZW1HOkCDRc78ggbqwwIJ2g='",

      # ALlow the script that removes `js-enabled` from body if there's an error
      # https://github.com/alphagov/govuk_template/blob/79340eb91ad8c4279d16da302765d0946d89b1ca/source/views/layouts/govuk_template.html.erb#L112-L113
      "'sha256-+6WnXIl4mbFTCARd8N3COQmT3bJJmo32N8q8ZSQAIcU='",

      # In browsers that don't support the sha256 whitelisting we allow unsafe
      # inline scripts
      "'unsafe-inline'"
    ].join(" ")

    # Allow styles from own domain and publishing domains. Also allow
    # "unsafe-inline" styles, because we use the `style=""` attribute on some HTML elements
    #
    # https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy/style-src
    policies << "style-src 'self' *.publishing.service.gov.uk 'unsafe-inline'"

    # Scripts can only load data using Ajax from Google Analytics and the publishing domains
    #
    # https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy/connect-src
    policies << "connect-src 'self' www.google-analytics.com *.publishing.service.gov.uk"

    # Disallow all <object>, <embed>, and <applet> elements
    #
    # https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy/object-src
    policies << "object-src 'none'"

    # Report any violations to Sentry (https://sentry.io/govuk/govuk-frontend-csp)
    policies << "report-uri https://sentry.io/api/1377947/security/?sentry_key=f7898bf4858d436aa3568ae042371b94"

    policies.join("; ") + ";"
  end
end

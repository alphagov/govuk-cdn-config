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

    # Allow images from the current domain, Google Analytics (the tracking pixel),
    # and publishing domains. Also allow `data:` images for Base64-encoded images
    # in CSS like:
    #
    # https://github.com/alphagov/service-manual-frontend/blob/1db99ed48de0dfc794b9686a98e6c62f8435ae80/app/assets/stylesheets/modules/_search.scss#L106
    #
    # https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy/img-src
    policies << "img-src 'self' data: www.google-analytics.com *.publishing.service.gov.uk"

    # script-src determines the scripts that the browser can load
    #
    # https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy/script-src
    policies << [
      # Allow scripts from Google Analytics and publishing domains
      "script-src 'self' www.google-analytics.com ssl.google-analytics.com *.publishing.service.gov.uk",

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

    # Allow fonts to be loaded from data-uri's (this is the old way of doing things)
    # or from the publishing asset domains.
    #
    # https://www.staging.publishing.service.gov.uk/apply-for-a-licence/test-licence/westminster/apply-1
    #
    # https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy/font-src
    policies << "font-src data: *.publishing.service.gov.uk"

    # https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy/connect-src
    policies << [
      # Scripts can only load data using Ajax from Google Analytics and the publishing domains
      "connect-src 'self' www.google-analytics.com *.publishing.service.gov.uk",

      # Allow connecting to web chat from HMRC contact pages like
      # https://www.staging.publishing.service.gov.uk/government/organisations/hm-revenue-customs/contact/child-benefit
      "www.tax.service.gov.uk",

      # Allow connecting to Verify to check whether the user is logged in
      # https://www.staging.publishing.service.gov.uk/log-in-file-self-assessment-tax-return/sign-in/prove-identity
      "www.signin.service.gov.uk",
    ].join(" ")

    # Disallow all <object>, <embed>, and <applet> elements
    #
    # https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy/object-src
    policies << "object-src 'none'"

    # Report any violations to Sentry (https://sentry.io/govuk/govuk-frontend-csp)
    policies << "report-uri https://sentry.io/api/1377947/security/?sentry_key=f7898bf4858d436aa3568ae042371b94"

    policies.join("; ") + ";"
  end
end

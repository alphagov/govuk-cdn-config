backend F_origin {
    .connect_timeout = 5s;
    .dynamic = true;
    .port = "443";
    .host = "foo";
    .first_byte_timeout = 15s;
    .max_connections = 200;
    .between_bytes_timeout = 10s;
    .share_key = "123";

    .ssl = true;
    .ssl_check_cert = always;
    .min_tls_version = "1.2";
    .ssl_cert_hostname = "foo";
    .ssl_sni_hostname = "foo";

    .probe = {
        .dummy = false;
        .request =
            "HEAD / HTTP/1.1"
            "Host: foo"
            "User-Agent: Fastly healthcheck (git version: )"
            "Connection: close";
        .threshold = 1;
        .window = 2;
        .timeout = 5s;
        .initial = 1;
        .expected_response = 200;
        .interval = 10s;
    }
}




acl allowed_ip_addresses {
}


sub vcl_recv {
  # Protect header from modification at the edge of the Fastly network
  # https://developer.fastly.com/reference/http-headers/Fastly-Client-IP
  if (fastly.ff.visits_this_service == 0 && req.restarts == 0) {
    set req.http.Fastly-Client-IP = client.ip;
  }

  # Original client address (e.g. for rate limiting).
  set req.http.True-Client-IP = req.http.Fastly-Client-IP;

  # Reset proxy headers at the boundary to our network so we can trust them in our stack
  set req.http.X-Forwarded-For = req.http.Fastly-Client-IP;
  set req.http.X-Forwarded-Host = req.http.host;
  set req.http.X-Forwarded-Server = server.hostname;

  # Discard user specified headers that we don't want to trust
  unset req.http.Client-IP;

  # Require authentication for PURGE requests
  set req.http.Fastly-Purge-Requires-Auth = "1";

  # Reset proxy headers at the boundary to our network.
  unset req.http.Client-IP;
  set req.http.X-Forwarded-For = req.http.Fastly-Client-IP;
  set req.http.X-Forwarded-Host = req.http.host;

  if (fastly.ff.visits_this_service == 0 && req.restarts == 0) {
    set req.http.Client-JA3 = tls.client.ja3_md5;
  }

  

  # Check whether the remote IP address is in the list of blocked IPs
  if (table.lookup(ip_address_denylist, client.ip)) {
    error 403 "Forbidden";
  }

  # Block requests that match a known bad signature
  if (req.restarts == 0 && fastly.ff.visits_this_service == 0) {
    if (table.lookup(ja3_signature_denylist, req.http.Client-JA3, "false") == "true") {
      error 403 "Forbidden";
    }
  }

  

  # Strip Accept-Encoding header if the content is already compressed
  if (req.http.Accept-Encoding) {
    if (req.url ~ "\.(jpeg|jpg|png|gif|gz|tgz|bz2|tbz|zip|flv|pdf|mp3|ogg)$") {
      remove req.http.Accept-Encoding;
    }
  }

  # Force SSL.
  if (!req.http.Fastly-SSL) {
     error 801 "Force SSL";
  }

  
  # some private vcl code

  # Serve a 404 Not Found response if request URL matches "/autodiscover/autodiscover.xml"
  if (req.url.path ~ "(?i)/autodiscover/autodiscover.xml$") {
    error 804 "Not Found";
  }

  # Redirect to security.txt for "/.well-known/security.txt" or "/security.txt"
  if (req.url.path ~ "(?i)^(?:/\.well[-_]known)?/security\.txt$") {
    error 805 "security.txt";
  }

  # Sort query params (improve cache hit rate)
  set req.url = querystring.sort(req.url);

  # Remove any Google Analytics campaign params
  set req.url = querystring.globfilter(req.url, "utm_*");

  # Serve from stale for 24 hours if origin is sick
  set req.grace = 24h;

  # Default backend, these details will be overwritten if other backends are
  # chosen
  set req.backend = F_origin;
  set req.http.Fastly-Backend-Name = "origin";

  # Set header to show recommended related links for Whitehall content. This is to be used
  # as a rollback mechanism should we ever need to stop showing these links.
  set req.http.Govuk-Use-Recommended-Related-Links = "true";

  # Set a request id header to allow requests to be traced through the stack
  set req.http.GOVUK-Request-Id = uuid.version4();

  if (req.url.path == "/") {
    # get rid of all query parameters
    set req.url = querystring.remove(req.url);
  }

  if (req.url.path ~ "^\/alerts(?:\/|$)") {
    # get rid of all query parameters
    set req.url = querystring.remove(req.url);
  }

  

  # Set a TLSversion request header for requests going to the Licensify application
  # This is used to block unsecure requests at the application level for payment security reasons and an absence of caching in Licensify
  if (req.url ~ "^/apply-for-a-licence/.*") {
    set req.http.TLSversion = tls.client.protocol;
  }

#FASTLY recv

  # GOV.UK accounts
  if (req.http.Cookie ~ "__Host-govuk_account_session") {
    set req.http.GOVUK-Account-Session = req.http.Cookie:__Host-govuk_account_session;
    set req.http.GOVUK-Account-Session-Exists = "1";

    if (req.http.GOVUK-Account-Session ~ "\$\$(.+)$") {
      # Not directly used by apps (govuk_personalisation extracts the
      # flash from the `GOVUK-Account-Session` header), but this is so
      # we can have `Vary: GOVUK-Account-Session-Flash` as a response
      # header for pages with success banners (etc).
      set req.http.GOVUK-Account-Session-Flash = re.group.1;
    }
  }

  if (req.request != "HEAD" && req.request != "GET" && req.request != "FASTLYPURGE") {
    return(pass);
  }

  # Begin dynamic section
  if (req.http.Cookie ~ "cookies_policy" && req.http.Cookie:cookies_policy ~ "%22usage%22:true") {
    set req.http.Usage-Cookies-Opt-In = "true";
    if (table.lookup(active_ab_tests, "Example") == "true") {
      if (req.http.User-Agent ~ "^GOV\.UK Crawler Worker") {
        set req.http.GOVUK-ABTest-Example = "A";
      } else if (req.url ~ "[\?\&]ABTest-Example=A(&|$)") {
        # Some users, such as remote testers, will be given a URL with a query string
        # to place them into a specific bucket.
        set req.http.GOVUK-ABTest-Example = "A";
      } else if (req.url ~ "[\?\&]ABTest-Example=B(&|$)") {
        # Some users, such as remote testers, will be given a URL with a query string
        # to place them into a specific bucket.
        set req.http.GOVUK-ABTest-Example = "B";
      } else if (req.http.Cookie ~ "ABTest-Example") {
        # Set the value of the header to whatever decision was previously made
        set req.http.GOVUK-ABTest-Example = req.http.Cookie:ABTest-Example;
        set req.http.GOVUK-ABTest-Example-Cookie = "sent_in_request";
      } else {
        declare local var.denominator_Example INTEGER;
        declare local var.denominator_Example_A INTEGER;
        declare local var.nominator_Example_A INTEGER;
        set var.nominator_Example_A = std.atoi(table.lookup(example_percentages, "A"));
        set var.denominator_Example += var.nominator_Example_A;
        declare local var.denominator_Example_B INTEGER;
        declare local var.nominator_Example_B INTEGER;
        set var.nominator_Example_B = std.atoi(table.lookup(example_percentages, "B"));
        set var.denominator_Example += var.nominator_Example_B;
        set var.denominator_Example_A = var.denominator_Example;
        if (randombool(var.nominator_Example_A, var.denominator_Example_A)) {
          set req.http.GOVUK-ABTest-Example = "A";
        } else {
          set req.http.GOVUK-ABTest-Example = "B";
        }
      }
    }
    if (table.lookup(active_ab_tests, "BankHolidaysTest") == "true") {
      if (req.http.User-Agent ~ "^GOV\.UK Crawler Worker") {
        set req.http.GOVUK-ABTest-BankHolidaysTest = "A";
      } else if (req.url ~ "[\?\&]ABTest-BankHolidaysTest=A(&|$)") {
        # Some users, such as remote testers, will be given a URL with a query string
        # to place them into a specific bucket.
        set req.http.GOVUK-ABTest-BankHolidaysTest = "A";
      } else if (req.url ~ "[\?\&]ABTest-BankHolidaysTest=B(&|$)") {
        # Some users, such as remote testers, will be given a URL with a query string
        # to place them into a specific bucket.
        set req.http.GOVUK-ABTest-BankHolidaysTest = "B";
      } else if (req.http.Cookie ~ "ABTest-BankHolidaysTest") {
        # Set the value of the header to whatever decision was previously made
        set req.http.GOVUK-ABTest-BankHolidaysTest = req.http.Cookie:ABTest-BankHolidaysTest;
        set req.http.GOVUK-ABTest-BankHolidaysTest-Cookie = "sent_in_request";
      } else {
        declare local var.denominator_BankHolidaysTest INTEGER;
        declare local var.denominator_BankHolidaysTest_A INTEGER;
        declare local var.nominator_BankHolidaysTest_A INTEGER;
        set var.nominator_BankHolidaysTest_A = std.atoi(table.lookup(bankholidaystest_percentages, "A"));
        set var.denominator_BankHolidaysTest += var.nominator_BankHolidaysTest_A;
        declare local var.denominator_BankHolidaysTest_B INTEGER;
        declare local var.nominator_BankHolidaysTest_B INTEGER;
        set var.nominator_BankHolidaysTest_B = std.atoi(table.lookup(bankholidaystest_percentages, "B"));
        set var.denominator_BankHolidaysTest += var.nominator_BankHolidaysTest_B;
        set var.denominator_BankHolidaysTest_A = var.denominator_BankHolidaysTest;
        if (randombool(var.nominator_BankHolidaysTest_A, var.denominator_BankHolidaysTest_A)) {
          set req.http.GOVUK-ABTest-BankHolidaysTest = "A";
        } else {
          set req.http.GOVUK-ABTest-BankHolidaysTest = "B";
        }
      }
    }
    if (table.lookup(active_ab_tests, "EsSixPointSeven") == "true") {
      if (req.http.User-Agent ~ "^GOV\.UK Crawler Worker") {
        set req.http.GOVUK-ABTest-EsSixPointSeven = "A";
      } else if (req.url ~ "[\?\&]ABTest-EsSixPointSeven=A(&|$)") {
        # Some users, such as remote testers, will be given a URL with a query string
        # to place them into a specific bucket.
        set req.http.GOVUK-ABTest-EsSixPointSeven = "A";
      } else if (req.url ~ "[\?\&]ABTest-EsSixPointSeven=B(&|$)") {
        # Some users, such as remote testers, will be given a URL with a query string
        # to place them into a specific bucket.
        set req.http.GOVUK-ABTest-EsSixPointSeven = "B";
      } else if (req.http.Cookie ~ "ABTest-EsSixPointSeven") {
        # Set the value of the header to whatever decision was previously made
        set req.http.GOVUK-ABTest-EsSixPointSeven = req.http.Cookie:ABTest-EsSixPointSeven;
        set req.http.GOVUK-ABTest-EsSixPointSeven-Cookie = "sent_in_request";
      } else {
        declare local var.denominator_EsSixPointSeven INTEGER;
        declare local var.denominator_EsSixPointSeven_A INTEGER;
        declare local var.nominator_EsSixPointSeven_A INTEGER;
        set var.nominator_EsSixPointSeven_A = std.atoi(table.lookup(essixpointseven_percentages, "A"));
        set var.denominator_EsSixPointSeven += var.nominator_EsSixPointSeven_A;
        declare local var.denominator_EsSixPointSeven_B INTEGER;
        declare local var.nominator_EsSixPointSeven_B INTEGER;
        set var.nominator_EsSixPointSeven_B = std.atoi(table.lookup(essixpointseven_percentages, "B"));
        set var.denominator_EsSixPointSeven += var.nominator_EsSixPointSeven_B;
        set var.denominator_EsSixPointSeven_A = var.denominator_EsSixPointSeven;
        if (randombool(var.nominator_EsSixPointSeven_A, var.denominator_EsSixPointSeven_A)) {
          set req.http.GOVUK-ABTest-EsSixPointSeven = "A";
        } else {
          set req.http.GOVUK-ABTest-EsSixPointSeven = "B";
        }
      }
    }
  }
  # End dynamic section


  return(lookup);
}

sub vcl_fetch {
#FASTLY fetch

  # Enable brotli
  if ((beresp.status == 200 || beresp.status == 404) && (beresp.http.content-type ~ "^(text/html|application/x-javascript|text/css|application/javascript|text/javascript|application/json|application/vnd\.ms-fontobject|application/x-font-opentype|application/x-font-truetype|application/x-font-ttf|application/xml|font/eot|font/opentype|font/otf|image/svg\+xml|image/vnd\.microsoft\.icon|text/plain|text/xml)\s*($|;)" || req.url ~ "\.(css|js|html|eot|ico|otf|ttf|json|svg)($|\?)" ) ) {
    # always set vary to make sure uncompressed versions dont always win
    if (!beresp.http.Vary ~ "Accept-Encoding") {
      if (beresp.http.Vary) {
        set beresp.http.Vary = beresp.http.Vary ", Accept-Encoding";
      } else {
        set beresp.http.Vary = "Accept-Encoding";
      }
    }
    if (req.http.Accept-Encoding == "br") {
      set beresp.brotli = true;
    } elsif (req.http.Accept-Encoding == "gzip") {
      set beresp.gzip = true;
    }
  }

  set beresp.http.Fastly-Backend-Name = req.http.Fastly-Backend-Name;

  if ((beresp.status >= 500 && beresp.status <= 599) && req.restarts < 3 && (req.request == "GET" || req.request == "HEAD") && !beresp.http.No-Fallback) {
    set beresp.saintmode = 5s;
    return (restart);
  }

  if (req.restarts == 0) {
    # Keep stale for origin
    set beresp.grace = 24h;
  }

  if(req.restarts > 0 ) {
    set beresp.http.Fastly-Restarts = req.restarts;
  }

  # The only valid status from our mirrors is a 200. They cannot return e.g.
  # a 301 status code. All errors from the mirrors are set to 503 as they
  # cannot know whether or not a page actually exists (e.g. /search is a valid
  # URL but the mirror cannot return it). It should be noted that the 503 is
  # set only when the last mirror has been attempted.
  if (beresp.status != 200 && beresp.http.Fastly-Backend-Name ~ "^mirror") {
    if (req.restarts < 3 ){
      set beresp.saintmode = 5s;
      return (restart);
    } else {
      set beresp.status = 503;
    }
  }

  if (beresp.status >= 500 && beresp.status <= 599) {
    set req.http.Fastly-Cachetype = "ERROR";
    set beresp.ttl = 1s;
    set beresp.grace = 5s;
    if (beresp.http.Fastly-Backend-Name ~ "^mirror") {
      error 503 "Error page";
    }
    return (deliver);
  }

  if (beresp.http.Cache-Control ~ "private") {
    set req.http.Fastly-Cachetype = "PRIVATE";
    return (pass);
  }

  if (beresp.http.Cache-Control ~ "max-age=0") {
    return (pass);
  }

  if (beresp.http.Cache-Control ~ "no-(store|cache)") {
    return (pass);
  }

  # Fastly doesn't recognise 307 as cacheable by default as it is based on an
  # old version of Varnish that also lacked 307 support.
  if (beresp.status == 307) {
    set beresp.cacheable = true;
  }

  if (beresp.http.Expires || beresp.http.Surrogate-Control ~ "max-age" || beresp.http.Cache-Control ~"(s-maxage|max-age)") {
    # keep the ttl here
  } else {
    # apply the default ttl
    set beresp.ttl = 5000s;

    # Mirror buckets do not set cache headers by default. Override TTL and add cache-control with 15 minutes
    if (beresp.http.Fastly-Backend-Name ~ "^mirror") {
      set beresp.ttl = 900s;
      set beresp.http.Cache-Control = "max-age=900";
    }
  }

  # Override default.vcl behaviour of return(pass).
  if (beresp.http.Set-Cookie) {
    return (deliver);
  }

  # Never cache responses which manipulate the user's session
  if (beresp.http.GOVUK-Account-End-Session) {
    return (pass);
  } else if (beresp.http.GOVUK-Account-Session) {
    return (pass);
  }
}

sub vcl_hit {
#FASTLY hit
}

sub vcl_miss {
#FASTLY miss
}

sub vcl_deliver {
  # GOV.UK accounts
  if (resp.http.GOVUK-Account-End-Session) {
    add resp.http.Set-Cookie = "__Host-govuk_account_session=; secure; httponly; samesite=lax; path=/; max-age=0";
    set resp.http.Cache-Control:no-store = "";
  } else if (resp.http.GOVUK-Account-Session) {
    add resp.http.Set-Cookie = "__Host-govuk_account_session=" + resp.http.GOVUK-Account-Session + "; secure; httponly; samesite=lax; path=/";
    set resp.http.Cache-Control:no-store = "";
  }

  if (resp.http.Vary ~ "GOVUK-Account-Session") {
    set resp.http.Vary:Cookie = "";
    set resp.http.Cache-Control:private = "";
  }

  unset resp.http.GOVUK-Account-Session;
  unset resp.http.GOVUK-Account-End-Session;
  unset resp.http.Vary:GOVUK-Account-Session;
  unset resp.http.Vary:GOVUK-Account-Session-Exists;
  unset resp.http.Vary:GOVUK-Account-Session-Flash;

  # Set the A/B cookies
  # Only set the A/B example cookie if the request is to the A/B test page. This
  # ensures that most visitors to the site aren't assigned an irrelevant test
  # cookie.
  if (req.url ~ "^/help/ab-testing"
    && req.http.User-Agent !~ "^GOV\.UK Crawler Worker"
    && req.http.GOVUK-ABTest-Example-Cookie != "sent_in_request") {
    # Set a fairly short cookie expiry because this is just an A/B test demo.
    add resp.http.Set-Cookie = "ABTest-Example=" req.http.GOVUK-ABTest-Example "; secure; expires=" now + 1d;
  }

  # Begin dynamic section
declare local var.expiry TIME;
if (req.http.Usage-Cookies-Opt-In == "true" && req.http.User-Agent !~ "^GOV\.UK Crawler Worker") {
  if (table.lookup(active_ab_tests, "BankHolidaysTest") == "true") {
    if (req.http.GOVUK-ABTest-BankHolidaysTest-Cookie != "sent_in_request" || req.url ~ "[\?\&]ABTest-BankHolidaysTest") {
      set var.expiry = time.add(now, std.integer2time(std.atoi(table.lookup(ab_test_expiries, "BankHolidaysTest"))));
      add resp.http.Set-Cookie = "ABTest-BankHolidaysTest=" req.http.GOVUK-ABTest-BankHolidaysTest "; secure; expires=" var.expiry "; path=/";
    }
  }
  if (table.lookup(active_ab_tests, "EsSixPointSeven") == "true") {
    if (req.http.GOVUK-ABTest-EsSixPointSeven-Cookie != "sent_in_request" || req.url ~ "[\?\&]ABTest-EsSixPointSeven") {
      set var.expiry = time.add(now, std.integer2time(std.atoi(table.lookup(ab_test_expiries, "EsSixPointSeven"))));
      add resp.http.Set-Cookie = "ABTest-EsSixPointSeven=" req.http.GOVUK-ABTest-EsSixPointSeven "; secure; expires=" var.expiry "; path=/";
    }
  }
}
  # End dynamic section

#FASTLY deliver
}

sub vcl_error {
  if (obj.status == 801) {
    set obj.status = 301;
    set obj.response = "Moved Permanently";
    set obj.http.Location = "https://" req.http.host req.url;
    set obj.http.Fastly-Backend-Name = "force_ssl";
    synthetic {""};
    return (deliver);
  }

  # Arbitrary 302 redirects called from vcl_recv.
  if (obj.status == 802) {
    set obj.status = 302;
    set obj.http.Location = "https://" req.http.host obj.response;
    set obj.response = "Moved";
    synthetic {""};
    return (deliver);
  }

  if (obj.status == 804) {
    set obj.status = 404;
    set obj.response = "Not Found";
    set obj.http.Fastly-Backend-Name = "force_not_found";

    synthetic {"
      <!DOCTYPE html>
      <html>
        <head>
          <title>Welcome to GOV.UK</title>
          <style>
            body { font-family: Arial, sans-serif; margin: 0; }
            header { background: black; }
            h1 { color: white; font-size: 29px; margin: 0 auto; padding: 10px; max-width: 990px; }
            p { color: black; margin: 30px auto; max-width: 990px; }
          </style>
        </head>
        <body>
          <header><h1>GOV.UK</h1></header>
          <p>We cannot find the page you're looking for. Please try searching on <a href="https://www.gov.uk/">GOV.UK</a>.</p>
        </body>
      </html>"};

    return (deliver);
  }

# Error 805
  # 302 redirect to vdp.cabinetoffice.gov.uk called from vcl_recv.
  if (obj.status == 805) {
    set obj.status = 302;
    set obj.http.Location = "https://vdp.cabinetoffice.gov.uk/.well-known/security.txt";
    set obj.response = "Moved";
    synthetic {""};
    return (deliver);
  }

  

  # Serve stale from error subroutine as recommended in:
  # https://docs.fastly.com/guides/performance-tuning/serving-stale-content
  # The use of `req.restarts == 0` condition is to enforce the restriction
  # of serving stale only when the backend is the origin.
  if ((req.restarts == 0) && (obj.status >= 500 && obj.status < 600)) {
    /* deliver stale object if it is available */
    if (stale.exists) {
      return(deliver_stale);
    }
  }

  # Assume we've hit vcl_error() because the backend is unavailable
  # for the first two retries. By restarting, vcl_recv() will try
  # serving from stale before failing over to the mirrors.
  if (req.restarts < 3) {
    return (restart);
  }

  set obj.http.Fastly-Backend-Name = "error";
  synthetic {"
    <!DOCTYPE html>
    <html>
      <head>
        <title>Welcome to GOV.UK</title>
        <style>
          body { font-family: Arial, sans-serif; margin: 0; }
          header { background: black; }
          h1 { color: white; font-size: 29px; margin: 0 auto; padding: 10px; max-width: 990px; }
          p { color: black; margin: 30px auto; max-width: 990px; }
        </style>
      </head>
      <body>
        <header><h1>GOV.UK</h1></header>
        <p>We're experiencing technical difficulties. Please try again later.</p>
      </body>
    </html>"};

  return (deliver);

#FASTLY error
}

# pipe cannot be included.

sub vcl_pass {
#FASTLY pass
}

sub vcl_hash {
#FASTLY hash
}

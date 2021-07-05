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


# Mirror backend for S3
backend F_mirrorS3 {
    .connect_timeout = 1s;
    .dynamic = true;
    .port = "443";
    .host = "bar";
    .first_byte_timeout = 15s;
    .max_connections = 200;
    .between_bytes_timeout = 10s;
    .share_key = "123";

    .ssl = true;
    .ssl_check_cert = always;
    .min_tls_version = "1.2";
    .ssl_cert_hostname = "bar";
    .ssl_sni_hostname = "bar";

    .probe = {
        .request =
            "HEAD / HTTP/1.1"
            "Host: bar"
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

# Mirror backend for S3 replica
backend F_mirrorS3Replica {
    .connect_timeout = 1s;
    .dynamic = true;
    .port = "443";
    .host = "s3-mirror-replica.aws.com";
    .first_byte_timeout = 15s;
    .max_connections = 200;
    .between_bytes_timeout = 10s;
    .share_key = "123";

    .ssl = true;
    .ssl_check_cert = always;
    .min_tls_version = "1.2";
    .ssl_cert_hostname = "s3-mirror-replica.aws.com";
    .ssl_sni_hostname = "s3-mirror-replica.aws.com";

    .probe = {
        .request =
            "HEAD / HTTP/1.1"
            "Host: s3-mirror-replica.aws.com"
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

# Mirror backend for GCS
backend F_mirrorGCS {
    .connect_timeout = 1s;
    .dynamic = true;
    .port = "443";
    .host = "gcs-mirror.google.com";
    .first_byte_timeout = 15s;
    .max_connections = 200;
    .between_bytes_timeout = 10s;
    .share_key = "123";

    .ssl = true;
    .ssl_check_cert = always;
    .min_tls_version = "1.2";
    .ssl_cert_hostname = "gcs-mirror.google.com";
    .ssl_sni_hostname = "gcs-mirror.google.com";

    .probe = {
        .request =
            "HEAD / HTTP/1.1"
            "Host: gcs-mirror.google.com"
            "User-Agent: Fastly healthcheck (git version: )"
            "Connection: close";
        .threshold = 1;
        .window = 2;
        .timeout = 5s;
        .initial = 1;
        .expected_response = 403;
        .interval = 10s;
    }
}


acl purge_ip_allowlist {
  "37.26.93.252";     # Skyscape mirrors
  "31.210.241.100";   # Carrenza mirrors

  "31.210.245.70";    # Carrenza Staging
  "18.202.183.143";   # AWS NAT GW1
  "18.203.90.80";     # AWS NAT GW2
  "18.203.108.248";   # AWS NAT GW3

  "23.235.32.0"/20;   # Fastly cache node
  "43.249.72.0"/22;   # Fastly cache node
  "103.244.50.0"/24;  # Fastly cache node
  "103.245.222.0"/23; # Fastly cache node
  "103.245.224.0"/24; # Fastly cache node
  "104.156.80.0"/20;  # Fastly cache node
  "151.101.0.0"/16;   # Fastly cache node
  "157.52.64.0"/18;   # Fastly cache node
  "172.111.64.0"/18;  # Fastly cache node
  "185.31.16.0"/22;   # Fastly cache node
  "199.27.72.0"/21;   # Fastly cache node
  "199.232.0.0"/16;   # Fastly cache node
  "202.21.128.0"/24;  # Fastly cache node
  "203.57.145.0"/24;  # Fastly cache node
  "167.82.0.0"/17;    # Fastly cache node
  "167.82.128.0"/20;  # Fastly cache node
  "167.82.160.0"/20;  # Fastly cache node
  "167.82.224.0"/20;  # Fastly cache node
}


acl allowed_ip_addresses {
  
}


sub vcl_recv {

  # Require authentication for FASTLYPURGE requests unless from IP in ACL
  if (req.request == "FASTLYPURGE" && client.ip !~ purge_ip_allowlist) {
    set req.http.Fastly-Purge-Requires-Auth = "1";
  }

  
  # Only allow connections from allowed IP addresses in staging
  if (! (client.ip ~ allowed_ip_addresses)) {
    error 403 "Forbidden";
  }
  

  # Check whether the remote IP address is in the list of blocked IPs
  if (table.lookup(ip_address_denylist, client.ip)) {
    error 403 "Forbidden";
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

  if (req.url.path == "/find-coronavirus-local-restrictions") {
    # get rid of all but the postcode param
    set req.url = querystring.filter_except(req.url, "postcode");
  }

  if (req.url.path == "/") {
    # get rid of all query parameters
    set req.url = querystring.remove(req.url);
  }

  

  # Save original request url because req.url changes after restarts.
  if (req.restarts < 1) {
    set req.http.original-url = req.url;
  }

  # Common config when failover to mirror buckets
  if (req.restarts > 0) {
    set req.url = req.http.original-url;

    # Don't serve from stale for mirrors
    set req.grace = 0s;
    set req.http.Fastly-Failover = "1";

    # Requests to home page, rewrite to index.html
    if (req.url ~ "^/?([\?#].*)?$") {
      set req.url = regsub(req.url, "^/?([\?#].*)?$", "/index.html\1");
    }

    # Replace multiple /
    set req.url = regsuball(req.url, "([^:])//+", "\1/");

    # Requests without document extension, rewrite adding .html
    if (req.url !~ "^([^#\?\s]+)\.(atom|chm|css|csv|diff|doc|docx|dot|dxf|eps|gif|gml|html|ico|ics|jpeg|jpg|JPG|js|json|kml|odp|ods|odt|pdf|PDF|png|ppt|pptx|ps|rdf|rtf|sch|txt|wsdl|xls|xlsm|xlsx|xlt|xml|xsd|xslt|zip)([\?#]+.*)?$") {
      set req.url = regsub(req.url, "^([^#\?\s]+)([\?#]+.*)?$", "\1.html\2");
    }
  }

  # Failover to primary s3 mirror.
  if (req.restarts == 1) {
      set req.backend = F_mirrorS3;
      set req.http.host = "bar";
      set req.http.Fastly-Backend-Name = "mirrorS3";

      # Add bucket directory prefix to all the requests
      set req.url = "/foo_" req.url;
  }

  # Failover to replica s3 mirror.
  if (req.restarts == 2) {
    set req.backend = F_mirrorS3Replica;
    set req.http.host = "s3-mirror-replica.aws.com";
    set req.http.Fastly-Backend-Name = "mirrorS3Replica";

    # Add bucket directory prefix to all the requests
    set req.url = "/s3-mirror-replica" req.url;
  }

  # Failover to GCS mirror.
  if (req.restarts > 2) {
    set req.backend = F_mirrorGCS;
    set req.http.host = "gcs-mirror.google.com";
    set req.http.Fastly-Backend-Name = "mirrorGCS";

    # Add bucket directory prefix to all the requests
    set req.url = "/gcs-mirror" req.url;

    set req.http.Date = now;
    set req.http.Authorization = "AWS gcs-mirror-access-id:" digest.hmac_sha1_base64("gcs-mirror-secret-key", "GET" LF LF LF now LF "/gcs-bucket" req.url.path);
  }

  # Add normalization vcl for Brotli support
  if (req.http.Fastly-Orig-Accept-Encoding) {
    if (req.http.Fastly-Orig-Accept-Encoding ~ "\bbr\b") {
      set req.http.Accept-Encoding = "br";
    }
  }
  

  # Protect header from modification at the edge of the Fastly network
  # https://developer.fastly.com/reference/http-headers/Fastly-Client-IP
  if (fastly.ff.visits_this_service == 0 && req.restarts == 0) {
    set req.http.Fastly-Client-IP = client.ip;
  }

  # Unspoofable original client address (e.g. for rate limiting).
  set req.http.True-Client-IP = req.http.Fastly-Client-IP;

  # Reset proxy headers at the boundary to our network.
  unset req.http.Client-IP;
  set req.http.X-Forwarded-For = req.http.Fastly-Client-IP;

  # Set a TLSversion request header for requests going to the Licensify application
  # This is used to block unsecure requests at the application level for payment security reasons and an absence of caching in Licensify
  if (req.url ~ "^/apply-for-a-licence/.*") {
    set req.http.TLSversion = tls.client.protocol;
  }


#FASTLY recv

  # RFC 134
  if (req.http.Cookie ~ "__Host-govuk_account_session") {
    set req.http.GOVUK-Account-Session = req.http.Cookie:__Host-govuk_account_session;
  }

  if (req.http.Cookie ~ "cookies_policy") {
    if (req.http.Cookie:cookies_policy ~ "%22usage%22:true" && req.http.User-Agent !~ "^GOV\.UK Crawler Worker" ) {
      if (table.lookup(active_ab_tests, "StartABusinessSegment") == "true") {
        declare local var.sab_variant STRING;

        # Always send this header if they've already got a cookie
        # This way, the cookie expiry gets updated in DELIVER, even if it's not a SaB page.
        # Thus sessions that that have >=2 SaB pages but more than half an hour apart
        # will be included.
        if (req.http.Cookie ~ "ABTest-start_a_business_segment=(A|B|C)") {
          set var.sab_variant = re.group.1;
          set req.http.GOVUK-ABTest-StartABusinessSegment = var.sab_variant;
        } else {
          # Cookie not set, default to A
          set var.sab_variant = "A";
        }

        if (table.lookup(start_a_business_ab_test_base_paths, querystring.remove(req.url)) == "true") {
          # Header so rendering app will know it's a SaB page (and the config is in just one place)
          set req.http.GOVUK-ABTest-IsStartABusinessPage = "true";
          # Segment header
          set req.http.GOVUK-ABTest-StartABusinessSegment = var.sab_variant;
        }

        if (querystring.remove(req.url) ~ "next-steps-for-your-business" || std.strlen(querystring.get(req.url, "hide-intervention")) > 0) {
          # If they've visited the SaB checker or opted not to see the banner,
          # we shouldn't show them an intervention again
          set req.http.GOVUK-ABTest-StartABusinessSegment = "C";
        }
      }
    }
  }

  if (req.request != "HEAD" && req.request != "GET" && req.request != "FASTLYPURGE") {
    return(pass);
  }

    # Begin dynamic section
if (req.http.Cookie ~ "cookies_policy" && req.http.Cookie:cookies_policy ~ "%22usage%22:true") {
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
  if (table.lookup(active_ab_tests, "AccountBankHols") == "true") {
    if (req.http.User-Agent ~ "^GOV\.UK Crawler Worker") {
      set req.http.GOVUK-ABTest-AccountBankHols = "A";
    } else if (req.url ~ "[\?\&]ABTest-AccountBankHols=A(&|$)") {
      # Some users, such as remote testers, will be given a URL with a query string
      # to place them into a specific bucket.
      set req.http.GOVUK-ABTest-AccountBankHols = "A";
    } else if (req.url ~ "[\?\&]ABTest-AccountBankHols=B(&|$)") {
      # Some users, such as remote testers, will be given a URL with a query string
      # to place them into a specific bucket.
      set req.http.GOVUK-ABTest-AccountBankHols = "B";
    } else if (req.http.Cookie ~ "ABTest-AccountBankHols") {
      # Set the value of the header to whatever decision was previously made
      set req.http.GOVUK-ABTest-AccountBankHols = req.http.Cookie:ABTest-AccountBankHols;
    } else {
      declare local var.denominator_AccountBankHols INTEGER;
      declare local var.denominator_AccountBankHols_A INTEGER;
      declare local var.nominator_AccountBankHols_A INTEGER;
      set var.nominator_AccountBankHols_A = std.atoi(table.lookup(accountbankhols_percentages, "A"));
      set var.denominator_AccountBankHols += var.nominator_AccountBankHols_A;
      declare local var.denominator_AccountBankHols_B INTEGER;
      declare local var.nominator_AccountBankHols_B INTEGER;
      set var.nominator_AccountBankHols_B = std.atoi(table.lookup(accountbankhols_percentages, "B"));
      set var.denominator_AccountBankHols += var.nominator_AccountBankHols_B;
      set var.denominator_AccountBankHols_A = var.denominator_AccountBankHols;
      if (randombool(var.nominator_AccountBankHols_A, var.denominator_AccountBankHols_A)) {
        set req.http.GOVUK-ABTest-AccountBankHols = "A";
      } else {
        set req.http.GOVUK-ABTest-AccountBankHols = "B";
      }
    }
  }
  if (table.lookup(active_ab_tests, "ExploreMenuAbTestable") == "true") {
    if (req.http.User-Agent ~ "^GOV\.UK Crawler Worker") {
      set req.http.GOVUK-ABTest-ExploreMenuAbTestable = "A";
    } else if (req.url ~ "[\?\&]ABTest-ExploreMenuAbTestable=A(&|$)") {
      # Some users, such as remote testers, will be given a URL with a query string
      # to place them into a specific bucket.
      set req.http.GOVUK-ABTest-ExploreMenuAbTestable = "A";
    } else if (req.url ~ "[\?\&]ABTest-ExploreMenuAbTestable=B(&|$)") {
      # Some users, such as remote testers, will be given a URL with a query string
      # to place them into a specific bucket.
      set req.http.GOVUK-ABTest-ExploreMenuAbTestable = "B";
    } else if (req.http.Cookie ~ "ABTest-ExploreMenuAbTestable") {
      # Set the value of the header to whatever decision was previously made
      set req.http.GOVUK-ABTest-ExploreMenuAbTestable = req.http.Cookie:ABTest-ExploreMenuAbTestable;
    } else {
      declare local var.denominator_ExploreMenuAbTestable INTEGER;
      declare local var.denominator_ExploreMenuAbTestable_A INTEGER;
      declare local var.nominator_ExploreMenuAbTestable_A INTEGER;
      set var.nominator_ExploreMenuAbTestable_A = std.atoi(table.lookup(exploremenuabtestable_percentages, "A"));
      set var.denominator_ExploreMenuAbTestable += var.nominator_ExploreMenuAbTestable_A;
      declare local var.denominator_ExploreMenuAbTestable_B INTEGER;
      declare local var.nominator_ExploreMenuAbTestable_B INTEGER;
      set var.nominator_ExploreMenuAbTestable_B = std.atoi(table.lookup(exploremenuabtestable_percentages, "B"));
      set var.denominator_ExploreMenuAbTestable += var.nominator_ExploreMenuAbTestable_B;
      set var.denominator_ExploreMenuAbTestable_A = var.denominator_ExploreMenuAbTestable;
      if (randombool(var.nominator_ExploreMenuAbTestable_A, var.denominator_ExploreMenuAbTestable_A)) {
        set req.http.GOVUK-ABTest-ExploreMenuAbTestable = "A";
      } else {
        set req.http.GOVUK-ABTest-ExploreMenuAbTestable = "B";
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
}

sub vcl_hit {
#FASTLY hit
}

sub vcl_miss {
#FASTLY miss
}

sub vcl_deliver {
  # RFC 134
  if (resp.http.GOVUK-Account-End-Session) {
    add resp.http.Set-Cookie = "__Host-govuk_account_session=; secure; httponly; samesite=lax; path=/; max-age=0";
    unset resp.http.GOVUK-Account-End-Session;
  } else if (resp.http.GOVUK-Account-Session) {
    add resp.http.Set-Cookie = "__Host-govuk_account_session=" + resp.http.GOVUK-Account-Session + "; secure; httponly; samesite=lax; path=/";
  }

  if (resp.http.Vary ~ "GOVUK-Account-Session") {
    unset resp.http.Vary:GOVUK-Account-Session;
    set resp.http.Vary:Cookie = "";
    set resp.http.Cache-Control:private = "";
  }

  unset resp.http.GOVUK-Account-Session;

  # Set the A/B cookies
  # Only set the A/B example cookie if the request is to the A/B test page. This
  # ensures that most visitors to the site aren't assigned an irrelevant test
  # cookie.
  if (req.url ~ "^/help/ab-testing"
    && req.http.User-Agent !~ "^GOV\.UK Crawler Worker"
    && req.http.Cookie !~ "ABTest-Example") {
    # Set a fairly short cookie expiry because this is just an A/B test demo.
    add resp.http.Set-Cookie = "ABTest-Example=" req.http.GOVUK-ABTest-Example "; secure; expires=" now + 1d;
  }

  # Begin dynamic section
  declare local var.expiry TIME;
  if (req.http.Cookie ~ "cookies_policy") {
    if (req.http.Cookie:cookies_policy ~ "%22usage%22:true") {
      if (table.lookup(active_ab_tests, "AccountBankHols") == "true") {
        if (req.http.Cookie !~ "ABTest-AccountBankHols" || req.url ~ "[\?\&]ABTest-AccountBankHols" && req.http.User-Agent !~ "^GOV\.UK Crawler Worker") {
          set var.expiry = time.add(now, std.integer2time(std.atoi(table.lookup(ab_test_expiries, "AccountBankHols"))));
          add resp.http.Set-Cookie = "ABTest-AccountBankHols=" req.http.GOVUK-ABTest-AccountBankHols "; secure; expires=" var.expiry "; path=/";
        }
      }
    }
  }
  if (req.http.Cookie ~ "cookies_policy") {
    if (req.http.Cookie:cookies_policy ~ "%22usage%22:true") {
      if (table.lookup(active_ab_tests, "ExploreMenuAbTestable") == "true") {
        if (req.http.Cookie !~ "ABTest-ExploreMenuAbTestable" || req.url ~ "[\?\&]ABTest-ExploreMenuAbTestable" && req.http.User-Agent !~ "^GOV\.UK Crawler Worker") {
          set var.expiry = time.add(now, std.integer2time(std.atoi(table.lookup(ab_test_expiries, "ExploreMenuAbTestable"))));
          add resp.http.Set-Cookie = "ABTest-ExploreMenuAbTestable=" req.http.GOVUK-ABTest-ExploreMenuAbTestable "; secure; expires=" var.expiry "; path=/";
        }
      }
    }
  }
  # End dynamic section

if (req.http.Cookie ~ "cookies_policy") {
  if (req.http.Cookie:cookies_policy ~ "%22usage%22:true" && req.http.User-Agent !~ "^GOV\.UK Crawler Worker"){
    if (table.lookup(active_ab_tests, "StartABusinessSegment") == "true") {
      declare local var.variant STRING;
      set var.variant = req.http.GOVUK-ABTest-StartABusinessSegment;

      if (std.strlen(var.variant) > 0) {
        declare local var.sab_expiry TIME;
        # Default to 30 mins for A and B variant
        set var.sab_expiry = time.add(now, 30m);

        if (var.variant == "C") {
          # If they have opted out of the banner or have visited the SaB checker
          # Expire in 26 weeks (approx 6 months)
          set var.sab_expiry = time.add(now, 26w);
        } else if (req.http.GOVUK-ABTest-IsStartABusinessPage == "true" && var.variant == "A") {
          # If the user is in variant A and has seen a SaB page then we need to move them to B
          # so they see the banner on the next SaB page they hit.
          set var.variant = "B";
        }

        add resp.http.Set-Cookie = "ABTest-start_a_business_segment=" var.variant "; secure; expires=" var.sab_expiry "; path=/";
      }
    }
  }
}
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
        <p>You can <a href="/coronavirus">find coronavirus information</a> on GOV.UK.</p>
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

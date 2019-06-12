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


acl purge_ip_whitelist {
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
}


acl allowed_ip_addresses {
  
}


sub vcl_recv {

  # Require authentication for FASTLYPURGE requests unless from IP in ACL
  if (req.request == "FASTLYPURGE" && client.ip !~ purge_ip_whitelist) {
    set req.http.Fastly-Purge-Requires-Auth = "1";
  }

  
  # Only allow connections from allowed IP addresses in staging
  if (! (client.ip ~ allowed_ip_addresses)) {
    error 403 "Forbidden";
  }
  

  # Check whether the remote IP address is in the list of blocked IPs
  if (table.lookup(ip_address_blacklist, client.ip)) {
    error 403 "Forbidden";
  }

  

  # Force SSL.
  if (!req.http.Fastly-SSL) {
     error 801 "Force SSL";
  }

  # Serve a 404 Not Found response if request URL matches "/autodiscover/autodiscover.xml"
  if (req.url.path ~ "(?i)/autodiscover/autodiscover.xml$") {
    error 804 "Not Found";
  }

  # Serve from stale for 24 hours if origin is sick
  set req.grace = 24h;

  # Default backend, these details will be overwritten if other backends are
  # chosen
  set req.backend = F_origin;
  set req.http.Fastly-Backend-Name = "origin";

  

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
  

  # Unspoofable original client address.
  set req.http.True-Client-IP = req.http.Fastly-Client-IP;

  # Set a TLSversion request header for requests going to the Licensify application
  # This is used to block unsecure requests at the application level for payment security reasons and an absence of caching in Licensify
  if (req.url ~ "^/apply-for-a-licence/.*") {
    set req.http.TLSversion = tls.client.protocol;
  }


#FASTLY recv

  if (req.request != "HEAD" && req.request != "GET" && req.request != "FASTLYPURGE") {
    return(pass);
  }

    # Begin dynamic section
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
if (table.lookup(active_ab_tests, "ViewDrivingLicence") == "true") {
  if (req.http.User-Agent ~ "^GOV\.UK Crawler Worker") {
    set req.http.GOVUK-ABTest-ViewDrivingLicence = "A";
  } else if (req.url ~ "[\?\&]ABTest-ViewDrivingLicence=A(&|$)") {
    # Some users, such as remote testers, will be given a URL with a query string
    # to place them into a specific bucket.
    set req.http.GOVUK-ABTest-ViewDrivingLicence = "A";
  } else if (req.url ~ "[\?\&]ABTest-ViewDrivingLicence=B(&|$)") {
    # Some users, such as remote testers, will be given a URL with a query string
    # to place them into a specific bucket.
    set req.http.GOVUK-ABTest-ViewDrivingLicence = "B";
  } else if (req.http.Cookie ~ "ABTest-ViewDrivingLicence") {
    # Set the value of the header to whatever decision was previously made
    set req.http.GOVUK-ABTest-ViewDrivingLicence = req.http.Cookie:ABTest-ViewDrivingLicence;
  } else {
    declare local var.denominator_ViewDrivingLicence INTEGER;
    declare local var.denominator_ViewDrivingLicence_A INTEGER;
    declare local var.nominator_ViewDrivingLicence_A INTEGER;
    set var.nominator_ViewDrivingLicence_A = std.atoi(table.lookup(viewdrivinglicence_percentages, "A"));
    set var.denominator_ViewDrivingLicence += var.nominator_ViewDrivingLicence_A;
    declare local var.denominator_ViewDrivingLicence_B INTEGER;
    declare local var.nominator_ViewDrivingLicence_B INTEGER;
    set var.nominator_ViewDrivingLicence_B = std.atoi(table.lookup(viewdrivinglicence_percentages, "B"));
    set var.denominator_ViewDrivingLicence += var.nominator_ViewDrivingLicence_B;
    set var.denominator_ViewDrivingLicence_A = var.denominator_ViewDrivingLicence;
    if (randombool(var.nominator_ViewDrivingLicence_A, var.denominator_ViewDrivingLicence_A)) {
      set req.http.GOVUK-ABTest-ViewDrivingLicence = "A";
    } else {
      set req.http.GOVUK-ABTest-ViewDrivingLicence = "B";
    }
  }
}
if (table.lookup(active_ab_tests, "FinderAnswerABTest") == "true") {
  if (req.http.User-Agent ~ "^GOV\.UK Crawler Worker") {
    set req.http.GOVUK-ABTest-FinderAnswerABTest = "A";
  } else if (req.url ~ "[\?\&]ABTest-FinderAnswerABTest=A(&|$)") {
    # Some users, such as remote testers, will be given a URL with a query string
    # to place them into a specific bucket.
    set req.http.GOVUK-ABTest-FinderAnswerABTest = "A";
  } else if (req.url ~ "[\?\&]ABTest-FinderAnswerABTest=B(&|$)") {
    # Some users, such as remote testers, will be given a URL with a query string
    # to place them into a specific bucket.
    set req.http.GOVUK-ABTest-FinderAnswerABTest = "B";
  } else if (req.http.Cookie ~ "ABTest-FinderAnswerABTest") {
    # Set the value of the header to whatever decision was previously made
    set req.http.GOVUK-ABTest-FinderAnswerABTest = req.http.Cookie:ABTest-FinderAnswerABTest;
  } else {
    declare local var.denominator_FinderAnswerABTest INTEGER;
    declare local var.denominator_FinderAnswerABTest_A INTEGER;
    declare local var.nominator_FinderAnswerABTest_A INTEGER;
    set var.nominator_FinderAnswerABTest_A = std.atoi(table.lookup(finderanswerabtest_percentages, "A"));
    set var.denominator_FinderAnswerABTest += var.nominator_FinderAnswerABTest_A;
    declare local var.denominator_FinderAnswerABTest_B INTEGER;
    declare local var.nominator_FinderAnswerABTest_B INTEGER;
    set var.nominator_FinderAnswerABTest_B = std.atoi(table.lookup(finderanswerabtest_percentages, "B"));
    set var.denominator_FinderAnswerABTest += var.nominator_FinderAnswerABTest_B;
    set var.denominator_FinderAnswerABTest_A = var.denominator_FinderAnswerABTest;
    if (randombool(var.nominator_FinderAnswerABTest_A, var.denominator_FinderAnswerABTest_A)) {
      set req.http.GOVUK-ABTest-FinderAnswerABTest = "A";
    } else {
      set req.http.GOVUK-ABTest-FinderAnswerABTest = "B";
    }
  }
}
# End dynamic section


  return(lookup);
}

sub vcl_fetch {
#FASTLY fetch

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

  # The only valid status from our mirrors is a 200. They cannot return e.g.
  # a 301 status code. All errors from the mirrors are set to 503 as they
  # cannot know whether or not a page actually exists (e.g. /search is a valid
  # URL but the mirror cannot return it).
  if (beresp.status != 200 && beresp.http.Fastly-Backend-Name ~ "^mirror") {
    set beresp.status = 503;
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
  if (table.lookup(active_ab_tests, "ViewDrivingLicence") == "true") {
    if (req.http.Cookie !~ "ABTest-ViewDrivingLicence" || req.url ~ "[\?\&]ABTest-ViewDrivingLicence" && req.http.User-Agent !~ "^GOV\.UK Crawler Worker") {
      set var.expiry = time.add(now, std.integer2time(std.atoi(table.lookup(ab_test_expiries, "ViewDrivingLicence"))));
      add resp.http.Set-Cookie = "ABTest-ViewDrivingLicence=" req.http.GOVUK-ABTest-ViewDrivingLicence "; secure; expires=" var.expiry "; path=/";
    }
  }
  if (table.lookup(active_ab_tests, "FinderAnswerABTest") == "true") {
    if (req.http.Cookie !~ "ABTest-FinderAnswerABTest" || req.url ~ "[\?\&]ABTest-FinderAnswerABTest" && req.http.User-Agent !~ "^GOV\.UK Crawler Worker") {
      set var.expiry = time.add(now, std.integer2time(std.atoi(table.lookup(ab_test_expiries, "FinderAnswerABTest"))));
      add resp.http.Set-Cookie = "ABTest-FinderAnswerABTest=" req.http.GOVUK-ABTest-FinderAnswerABTest "; secure; expires=" var.expiry "; path=/";
    }
  }
  # End dynamic section

  # Set the TLS version session cookie with the raw protocol version from
  # Fastly only if it isn't already set. We also check for a null TLS value,
  # which can occur when trying to access over HTTP (http>https upgrading).
  if (tls.client.protocol && req.http.Cookie !~ "TLSversion") {
    add resp.http.Set-Cookie = "TLSversion=" tls.client.protocol "; secure";
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

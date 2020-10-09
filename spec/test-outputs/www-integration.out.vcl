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



acl purge_ip_allowlist {
  "37.26.93.252";     # Skyscape mirrors
  "31.210.241.100";   # Carrenza mirrors

  "34.248.229.46";    # AWS Integration NAT gateway
  "34.248.44.175";    # AWS Integration NAT gateway
  "52.51.97.232";     # AWS Integration NAT gateway

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

  

  # Check whether the remote IP address is in the list of blocked IPs
  if (table.lookup(ip_address_denylist, client.ip)) {
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

  # Set header to show recommended related links for Whitehall content. This is to be used
  # as a rollback mechanism should we ever need to stop showing these links.
  set req.http.Govuk-Use-Recommended-Related-Links = "true";

  

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
if (req.http.Cookie ~ "cookies_policy") {
  if (req.http.Cookie:cookies_policy ~ "%22usage%22:true") {
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
    if (table.lookup(active_ab_tests, "ElectricCarABTest") == "true") {
      if (req.http.User-Agent ~ "^GOV\.UK Crawler Worker") {
        set req.http.GOVUK-ABTest-ElectricCarABTest = "A";
      } else if (req.url ~ "[\?\&]ABTest-ElectricCarABTest=A(&|$)") {
        # Some users, such as remote testers, will be given a URL with a query string
        # to place them into a specific bucket.
        set req.http.GOVUK-ABTest-ElectricCarABTest = "A";
      } else if (req.url ~ "[\?\&]ABTest-ElectricCarABTest=B(&|$)") {
        # Some users, such as remote testers, will be given a URL with a query string
        # to place them into a specific bucket.
        set req.http.GOVUK-ABTest-ElectricCarABTest = "B";
      } else if (req.url ~ "[\?\&]ABTest-ElectricCarABTest=C(&|$)") {
        # Some users, such as remote testers, will be given a URL with a query string
        # to place them into a specific bucket.
        set req.http.GOVUK-ABTest-ElectricCarABTest = "C";
      } else if (req.url ~ "[\?\&]ABTest-ElectricCarABTest=D(&|$)") {
        # Some users, such as remote testers, will be given a URL with a query string
        # to place them into a specific bucket.
        set req.http.GOVUK-ABTest-ElectricCarABTest = "D";
      } else if (req.url ~ "[\?\&]ABTest-ElectricCarABTest=E(&|$)") {
        # Some users, such as remote testers, will be given a URL with a query string
        # to place them into a specific bucket.
        set req.http.GOVUK-ABTest-ElectricCarABTest = "E";
      } else if (req.url ~ "[\?\&]ABTest-ElectricCarABTest=F(&|$)") {
        # Some users, such as remote testers, will be given a URL with a query string
        # to place them into a specific bucket.
        set req.http.GOVUK-ABTest-ElectricCarABTest = "F";
      } else if (req.url ~ "[\?\&]ABTest-ElectricCarABTest=G(&|$)") {
        # Some users, such as remote testers, will be given a URL with a query string
        # to place them into a specific bucket.
        set req.http.GOVUK-ABTest-ElectricCarABTest = "G";
      } else if (req.url ~ "[\?\&]ABTest-ElectricCarABTest=H(&|$)") {
        # Some users, such as remote testers, will be given a URL with a query string
        # to place them into a specific bucket.
        set req.http.GOVUK-ABTest-ElectricCarABTest = "H";
      } else if (req.http.Cookie ~ "ABTest-ElectricCarABTest") {
        # Set the value of the header to whatever decision was previously made
        set req.http.GOVUK-ABTest-ElectricCarABTest = req.http.Cookie:ABTest-ElectricCarABTest;
      } else {
        declare local var.denominator_ElectricCarABTest INTEGER;
        declare local var.denominator_ElectricCarABTest_A INTEGER;
        declare local var.nominator_ElectricCarABTest_A INTEGER;
        set var.nominator_ElectricCarABTest_A = std.atoi(table.lookup(electriccarabtest_percentages, "A"));
        set var.denominator_ElectricCarABTest += var.nominator_ElectricCarABTest_A;
        declare local var.denominator_ElectricCarABTest_B INTEGER;
        declare local var.nominator_ElectricCarABTest_B INTEGER;
        set var.nominator_ElectricCarABTest_B = std.atoi(table.lookup(electriccarabtest_percentages, "B"));
        set var.denominator_ElectricCarABTest += var.nominator_ElectricCarABTest_B;
        declare local var.denominator_ElectricCarABTest_C INTEGER;
        declare local var.nominator_ElectricCarABTest_C INTEGER;
        set var.nominator_ElectricCarABTest_C = std.atoi(table.lookup(electriccarabtest_percentages, "C"));
        set var.denominator_ElectricCarABTest += var.nominator_ElectricCarABTest_C;
        declare local var.denominator_ElectricCarABTest_D INTEGER;
        declare local var.nominator_ElectricCarABTest_D INTEGER;
        set var.nominator_ElectricCarABTest_D = std.atoi(table.lookup(electriccarabtest_percentages, "D"));
        set var.denominator_ElectricCarABTest += var.nominator_ElectricCarABTest_D;
        declare local var.denominator_ElectricCarABTest_E INTEGER;
        declare local var.nominator_ElectricCarABTest_E INTEGER;
        set var.nominator_ElectricCarABTest_E = std.atoi(table.lookup(electriccarabtest_percentages, "E"));
        set var.denominator_ElectricCarABTest += var.nominator_ElectricCarABTest_E;
        declare local var.denominator_ElectricCarABTest_F INTEGER;
        declare local var.nominator_ElectricCarABTest_F INTEGER;
        set var.nominator_ElectricCarABTest_F = std.atoi(table.lookup(electriccarabtest_percentages, "F"));
        set var.denominator_ElectricCarABTest += var.nominator_ElectricCarABTest_F;
        declare local var.denominator_ElectricCarABTest_G INTEGER;
        declare local var.nominator_ElectricCarABTest_G INTEGER;
        set var.nominator_ElectricCarABTest_G = std.atoi(table.lookup(electriccarabtest_percentages, "G"));
        set var.denominator_ElectricCarABTest += var.nominator_ElectricCarABTest_G;
        declare local var.denominator_ElectricCarABTest_H INTEGER;
        declare local var.nominator_ElectricCarABTest_H INTEGER;
        set var.nominator_ElectricCarABTest_H = std.atoi(table.lookup(electriccarabtest_percentages, "H"));
        set var.denominator_ElectricCarABTest += var.nominator_ElectricCarABTest_H;
        set var.denominator_ElectricCarABTest_A = var.denominator_ElectricCarABTest;
        set var.denominator_ElectricCarABTest_B = var.denominator_ElectricCarABTest_A;
        set var.denominator_ElectricCarABTest_B -= var.nominator_ElectricCarABTest_A;
        set var.denominator_ElectricCarABTest_C = var.denominator_ElectricCarABTest_B;
        set var.denominator_ElectricCarABTest_C -= var.nominator_ElectricCarABTest_B;
        set var.denominator_ElectricCarABTest_D = var.denominator_ElectricCarABTest_C;
        set var.denominator_ElectricCarABTest_D -= var.nominator_ElectricCarABTest_C;
        set var.denominator_ElectricCarABTest_E = var.denominator_ElectricCarABTest_D;
        set var.denominator_ElectricCarABTest_E -= var.nominator_ElectricCarABTest_D;
        set var.denominator_ElectricCarABTest_F = var.denominator_ElectricCarABTest_E;
        set var.denominator_ElectricCarABTest_F -= var.nominator_ElectricCarABTest_E;
        set var.denominator_ElectricCarABTest_G = var.denominator_ElectricCarABTest_F;
        set var.denominator_ElectricCarABTest_G -= var.nominator_ElectricCarABTest_F;
        if (randombool(var.nominator_ElectricCarABTest_A, var.denominator_ElectricCarABTest_A)) {
          set req.http.GOVUK-ABTest-ElectricCarABTest = "A";
        } else if (randombool(var.nominator_ElectricCarABTest_B, var.denominator_ElectricCarABTest_B)) {
          set req.http.GOVUK-ABTest-ElectricCarABTest = "B";
        } else if (randombool(var.nominator_ElectricCarABTest_C, var.denominator_ElectricCarABTest_C)) {
          set req.http.GOVUK-ABTest-ElectricCarABTest = "C";
        } else if (randombool(var.nominator_ElectricCarABTest_D, var.denominator_ElectricCarABTest_D)) {
          set req.http.GOVUK-ABTest-ElectricCarABTest = "D";
        } else if (randombool(var.nominator_ElectricCarABTest_E, var.denominator_ElectricCarABTest_E)) {
          set req.http.GOVUK-ABTest-ElectricCarABTest = "E";
        } else if (randombool(var.nominator_ElectricCarABTest_F, var.denominator_ElectricCarABTest_F)) {
          set req.http.GOVUK-ABTest-ElectricCarABTest = "F";
        } else if (randombool(var.nominator_ElectricCarABTest_G, var.denominator_ElectricCarABTest_G)) {
          set req.http.GOVUK-ABTest-ElectricCarABTest = "G";
        } else {
          set req.http.GOVUK-ABTest-ElectricCarABTest = "H";
        }
      }
    }
    if (table.lookup(active_ab_tests, "TransitionUrgency2") == "true") {
      if (req.http.User-Agent ~ "^GOV\.UK Crawler Worker") {
        set req.http.GOVUK-ABTest-TransitionUrgency2 = "A";
      } else if (req.url ~ "[\?\&]ABTest-TransitionUrgency2=A(&|$)") {
        # Some users, such as remote testers, will be given a URL with a query string
        # to place them into a specific bucket.
        set req.http.GOVUK-ABTest-TransitionUrgency2 = "A";
      } else if (req.url ~ "[\?\&]ABTest-TransitionUrgency2=B(&|$)") {
        # Some users, such as remote testers, will be given a URL with a query string
        # to place them into a specific bucket.
        set req.http.GOVUK-ABTest-TransitionUrgency2 = "B";
      } else if (req.http.Cookie ~ "ABTest-TransitionUrgency2") {
        # Set the value of the header to whatever decision was previously made
        set req.http.GOVUK-ABTest-TransitionUrgency2 = req.http.Cookie:ABTest-TransitionUrgency2;
      } else {
        declare local var.denominator_TransitionUrgency2 INTEGER;
        declare local var.denominator_TransitionUrgency2_A INTEGER;
        declare local var.nominator_TransitionUrgency2_A INTEGER;
        set var.nominator_TransitionUrgency2_A = std.atoi(table.lookup(transitionurgency2_percentages, "A"));
        set var.denominator_TransitionUrgency2 += var.nominator_TransitionUrgency2_A;
        declare local var.denominator_TransitionUrgency2_B INTEGER;
        declare local var.nominator_TransitionUrgency2_B INTEGER;
        set var.nominator_TransitionUrgency2_B = std.atoi(table.lookup(transitionurgency2_percentages, "B"));
        set var.denominator_TransitionUrgency2 += var.nominator_TransitionUrgency2_B;
        set var.denominator_TransitionUrgency2_A = var.denominator_TransitionUrgency2;
        if (randombool(var.nominator_TransitionUrgency2_A, var.denominator_TransitionUrgency2_A)) {
          set req.http.GOVUK-ABTest-TransitionUrgency2 = "A";
        } else {
          set req.http.GOVUK-ABTest-TransitionUrgency2 = "B";
        }
      }
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
  if (req.http.Cookie ~ "cookies_policy") {
    if (req.http.Cookie:cookies_policy ~ "%22usage%22:true") {
      if (table.lookup(active_ab_tests, "ElectricCarABTest") == "true") {
        if (req.http.Cookie !~ "ABTest-ElectricCarABTest" || req.url ~ "[\?\&]ABTest-ElectricCarABTest" && req.http.User-Agent !~ "^GOV\.UK Crawler Worker") {
          set var.expiry = time.add(now, std.integer2time(std.atoi(table.lookup(ab_test_expiries, "ElectricCarABTest"))));
          add resp.http.Set-Cookie = "ABTest-ElectricCarABTest=" req.http.GOVUK-ABTest-ElectricCarABTest "; secure; expires=" var.expiry "; path=/";
        }
      }
    }
  }
  if (req.http.Cookie ~ "cookies_policy") {
    if (req.http.Cookie:cookies_policy ~ "%22usage%22:true") {
      if (table.lookup(active_ab_tests, "TransitionUrgency2") == "true") {
        if (req.http.Cookie !~ "ABTest-TransitionUrgency2" || req.url ~ "[\?\&]ABTest-TransitionUrgency2" && req.http.User-Agent !~ "^GOV\.UK Crawler Worker") {
          set var.expiry = time.add(now, std.integer2time(std.atoi(table.lookup(ab_test_expiries, "TransitionUrgency2"))));
          add resp.http.Set-Cookie = "ABTest-TransitionUrgency2=" req.http.GOVUK-ABTest-TransitionUrgency2 "; secure; expires=" var.expiry "; path=/";
        }
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

backend F_carrenzaorigin {
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
            "HEAD /__canary__ HTTP/1.1"
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
backend F_awsorigin {
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
            "HEAD /__canary__ HTTP/1.1"
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

# Mirror backend for provider 0
backend F_mirror1 {
    .connect_timeout = 1s;
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
            "HEAD /__canary__ HTTP/1.1"
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

backend sick_force_grace {
  .host = "127.0.0.1";
  .port = "1";
  .probe = {
    .request = "invalid";
    .interval = 365d;
    .initial = 0;
  }
}


acl purge_ip_whitelist {
  "37.26.93.252";     # Skyscape mirrors
  "31.210.241.100";   # Carrenza mirrors

  "31.210.245.86";    # Carrenza Production
  "18.202.136.43";    # AWS Production
  "34.246.209.74";    # AWS Production
  "34.253.57.8";      # AWS Production

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

sub vcl_recv {

  # Allow FASTLYPURGE from IPs defined in the ACL only, else return a HTTP 403
  if (req.request == "FASTLYPURGE") {
    if (client.ip ~ purge_ip_whitelist) {
      return (lookup);
    }
    error 403 "Forbidden";
  }

  # Force SSL.
  if (!req.http.Fastly-SSL) {
     error 801 "Force SSL";
  }

  # Serve and log an empty response for analytics purposes
  if (req.url ~ "^/static/a\?") {
     error 802 "OK";
  }

  # Serve from stale for 24 hours if origin is sick
  set req.grace = 24h;

  # Default backend.
  set req.backend = F_awsorigin;
  set req.http.Fastly-Backend-Name = "awsorigin";
  set req.http.host = "foo";

  if (req.url ~ "^/asset-manager" ||
      req.url ~ "^/government/uploads" ||
      req.url ~ "^/media" ||
      req.url ~ "^/government/assets" ||
      req.url ~ "^/government/placeholder"
      ) {
      set req.backend = F_carrenzaorigin;
      set req.http.Fastly-Backend-Name = "carrenzaorigin";
      set req.http.host = "foo";
  }

  # Serve stale if it exists.
  if (req.restarts > 0) {
    set req.backend = sick_force_grace;
    set req.http.Fastly-Backend-Name = "stale";
  }

  # Failover to mirror.
  if (req.restarts > 1) {
    # Don't serve from stale for mirrors
    set req.grace = 0s;
    set req.http.Fastly-Failover = "1";

    set req.backend = F_mirror1;
    set req.http.Fastly-Backend-Name = "mirror1";
    set req.http.host = "foo";
  }

  # FIXME: Prefer a fallback director if we move to Varnish 3
  if (req.restarts > 2) {
    set req.backend = F_mirrorS3;
    set req.http.host = "bar";
    set req.http.Fastly-Backend-Name = "mirrorS3";

    # Replace multiple /
    set req.url = regsuball(req.url, "([^:])//+", "\1/");

    # Rewrite adding bucket directory prefix
    set req.url = "/foo_" req.url;
  }

  # Unspoofable original client address.
  set req.http.True-Client-IP = req.http.Fastly-Client-IP;

#FASTLY recv

  if (req.request != "HEAD" && req.request != "GET" && req.request != "FASTLYPURGE") {
    return(pass);
  }

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

  if (beresp.status >= 500 && beresp.status <= 599) {
    set req.http.Fastly-Cachetype = "ERROR";
    set beresp.ttl = 1s;
    set beresp.grace = 5s;
    if (beresp.http.Fastly-Backend-Name ~ "mirrorS3") {
      error 503 "Error page";
    }
    return (deliver);
  }

  if (beresp.http.Expires || beresp.http.Surrogate-Control ~ "max-age" || beresp.http.Cache-Control ~"(s-maxage|max-age)") {
    # keep the ttl here
  } else {
    # apply the default ttl
    set beresp.ttl = 5000s;
    # S3 does not set cache headers by default. Override TTL and add cache-control with 15 minutes
    if (beresp.http.Fastly-Backend-Name ~ "mirrorS3") {
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
#FASTLY deliver
}

sub vcl_error {
  if (obj.status == 801) {
    set obj.status = 301;
    set obj.response = "Moved Permanently";
    set obj.http.Location = "https://" req.http.host req.url;
    synthetic {""};
    return (deliver);
  }

  if (obj.status == 802) {
    set obj.http.Content-Type = "text/plain";
    set obj.http.Access-Control-Allow-Origin = "*";
    set obj.status = 200;
    synthetic {""};
    return(deliver);
  }

  # Assume we've hit vcl_error() because the backend is unavailable
  # for the first two retries. By restarting, vcl_recv() will try
  # serving from stale before failing over to the mirrors.
  if (req.restarts < 3) {
    return (restart);
  }

  synthetic {"
    GOV.UK is experiencing technical difficulties now. Please try again later."};

  return (deliver);

#FASTLY error
}

sub vcl_pass {
#FASTLY pass
}

sub vcl_hash {
#FASTLY hash
}

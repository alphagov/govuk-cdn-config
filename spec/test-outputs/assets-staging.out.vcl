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
  "18.203.108.248";   # AWS Staging
  "18.202.183.143";   # AWS Staging
  "18.203.90.80";     # AWS Staging

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

sub vcl_recv {

  # Require authentication for FASTLYPURGE requests unless from IP in ACL
  if (req.request == "FASTLYPURGE" && client.ip !~ purge_ip_whitelist) {
    set req.http.Fastly-Purge-Requires-Auth = "1";
  }

  # Force SSL.
  if (!req.http.Fastly-SSL) {
     error 801 "Force SSL";
  }

  # Serve from stale for 24 hours if origin is sick
  set req.grace = 24h;

  # Default backend.
  set req.backend = F_awsorigin;
  set req.http.Fastly-Backend-Name = "awsorigin";
  set req.http.host = "foo";

  

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

    # Replace multiple /
    set req.url = regsuball(req.url, "([^:])//+", "\1/");
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

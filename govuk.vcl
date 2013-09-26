# >> custom backends
backend F_origin {
    .connect_timeout = 1s;
    .dynamic = true;
    .port = "443";
    .host = "www-origin.staging.alphagov.co.uk";
    .first_byte_timeout = 15s;
    .max_connections = 200;
    .between_bytes_timeout = 10s;
    .share_key = "fastly_service_id_govuk_staging";

    .ssl = true;
    .ssl_hostname = "www-origin.staging.alphagov.co.uk";

    .probe = {
        .request = "HEAD / HTTP/1.1" "Host: www-origin.staging.alphagov.co.uk" "Connection: close";
        .threshold = 3;
        .window = 5;
        .timeout = 0.5s;
        .initial = 2;
        .expected_response = 200;
        .interval = 5s;
      }
}
backend F_mirror {
    .connect_timeout = 1s;
    .dynamic = true;
    .port = "443";
    .host = "www-origin.mirror.provider0.production.govuk.service.gov.uk";
    .first_byte_timeout = 15s;
    .max_connections = 200;
    .between_bytes_timeout = 10s;
    .share_key = "fastly_service_id_govuk_staging";

    .ssl = true;
    .ssl_hostname = "www-origin.mirror.provider0.production.govuk.service.gov.uk";

    .probe = {
        .request = "HEAD / HTTP/1.1" "Host: www-origin.mirror.provider0.production.govuk.service.gov.uk" "Connection: close";
        .threshold = 3;
        .window = 5;
        .timeout = 0.5s;
        .initial = 2;
        .expected_response = 200;
        .interval = 5s;
      }
}
# << custom backends

sub vcl_recv {
  # >> custom recv
  # Unspoofable original client address.
  set req.http.True-Client-IP = req.http.Fastly-Client-IP;
  # << custom recv

#FASTLY recv

  # >> not reproduced by macro
  if (req.request != "HEAD" && req.request != "GET" && req.request != "PURGE") {
    return(pass);
  }

  return(lookup);
  # << not reproduced by macro
}

sub vcl_fetch {
#FASTLY fetch

  # >> not reproduced by macro
  if ((beresp.status == 500 || beresp.status == 503) && req.restarts < 1 && (req.request == "GET" || req.request == "HEAD")) {
    restart;
  }

  if(req.restarts > 0 ) {
    set beresp.http.Fastly-Restarts = req.restarts;
  }

  if (beresp.http.Set-Cookie) {
    set req.http.Fastly-Cachetype = "SETCOOKIE";
    return (pass);
  }

  if (beresp.http.Cache-Control ~ "private") {
    set req.http.Fastly-Cachetype = "PRIVATE";
    return (pass);
  }

  if (beresp.status == 500 || beresp.status == 503) {
    set req.http.Fastly-Cachetype = "ERROR";
    set beresp.ttl = 1s;
    set beresp.grace = 5s;
    return (deliver);
  }

  if (beresp.http.Expires || beresp.http.Surrogate-Control ~ "max-age" || beresp.http.Cache-Control ~"(s-maxage|max-age)") {
    # keep the ttl here
  } else {
    # apply the default ttl
    set beresp.ttl = 3600s;
  }
  # << not reproduced by macro
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
#FASTLY error
}

# <<
# pipe cannot be included.
# >>

sub vcl_pass {
#FASTLY pass
}

sub vcl_hash {
  # >> not reproduced by macro
  # `FASTLY hash` only appends `#####GENERATION#####`
  set req.hash += req.url;
  set req.hash += req.http.host;
  set req.hash += "#####GENERATION#####";
  return (hash);
  # << not reproduced by macro
}

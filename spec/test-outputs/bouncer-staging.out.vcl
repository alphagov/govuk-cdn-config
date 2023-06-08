
backend F_origin0 {
    .connect_timeout = 1s;
    .dynamic = true;
    .port = "80";
    .host = "bouncer.test.gov.uk";
    .first_byte_timeout = 15s;
    .max_connections = 200;
    .between_bytes_timeout = 10s;
    .share_key = "12345";

    .probe = {
        .request = "HEAD /healthcheck/ready HTTP/1.1"  "Host: bouncer.test.gov.uk" "Connection: close";
        .window = 2;
        .threshold = 1;
        .timeout = 2s;
        .interval = 5m;
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


acl purge_ip_allowlist {
  # See https://sites.google.com/a/digital.cabinet-office.gov.uk/gds/working-at-the-white-chapel-building/gds-internal-it/gds-internal-it-network-public-ip-addresses
  "213.86.153.211";  # GDS Office (BYOD VPN)
  "213.86.153.212";  # GDS Office
  "213.86.153.213";  # GDS Office
  "213.86.153.214";  # GDS Office
  "213.86.153.231";  # GDS Office (BYOD VPN)
  "213.86.153.235";  # GDS Office
  "213.86.153.236";  # GDS Office
  "213.86.153.237";  # GDS Office
  "51.149.8.0"/25;   # GDS Office (DR VPN)
  "51.149.8.128"/29; # GDS Office (DR BYOD VPN)
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

  # Require authentication for FASTLYPURGE requests unless from IP in ACL
  if (req.request == "FASTLYPURGE" && client.ip !~ purge_ip_allowlist) {
    set req.http.Fastly-Purge-Requires-Auth = "1";
  }

  # Serve a 404 Not Found response if request URL matches "/autodiscover/autodiscover.xml"
  if (req.url.path ~ "(?i)/autodiscover/autodiscover.xml$") {
    error 804 "Not Found";
  }

  # Redirect to security.txt for "/.well-known/security.txt" or "/security.txt"
  if (req.url.path ~ "(?i)^(?:/\.well[-_]known)?/security\.txt$") {
    error 805 "security.txt";
  }

  # Keep stale.
  set req.grace = 86400s;

  # Default backend.
  set req.backend = F_origin0;

  # Serve stale if it exists.
  if (req.restarts > 0) {
    set req.backend = sick_force_grace;
    set req.http.Fastly-Backend-Name = "stale";
  }


#FASTLY recv

  if (req.request != "HEAD" && req.request != "GET" && req.request != "PURGE") {
    return(pass);
  }

  return(lookup);
}

sub vcl_fetch {
#FASTLY fetch


  set beresp.grace = 86400s;

  if ((beresp.status == 500 || beresp.status == 503) && req.restarts < 2 && (req.request == "GET" || req.request == "HEAD")) {
    set beresp.saintmode = 5s;
    return (restart);
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

  # Assume we've hit vcl_error() because the backend is unavailable
  if (req.restarts < 2) {
    return (restart);
  }

  synthetic {"
    <!DOCTYPE html>
    <html>
      <head>
        <title>GOV.UK Redirect</title>
        <style>
          body { font-family: Arial, sans-serif; margin: 0; }
          header { background: black; }
          h1 { color: white; font-size: 29px; margin: 0 auto; padding: 10px; max-width: 990px; }
          p { color: black; margin: 30px auto; max-width: 990px; }
        </style>
      </head>
      <body>
        <header><h1>GOV.UK</h1></header>
        <p>We are experiencing technical difficulties.</p>
        <p>The page you requested may be available on <a href='https://www.gov.uk'>GOV.UK</a> or the <a href='http://www.nationalarchives.gov.uk/webarchive/'>UK Government Web Archive</a>.</p>
      </body>
    </html>"};

  set obj.status = 503;
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

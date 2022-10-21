# Backends
backend F_apt {
    .connect_timeout = 1s;
    .dynamic = true;
    .port = "443";
    .host = "foo";
    .first_byte_timeout = 15s;
    .max_connections = 200;
    .between_bytes_timeout = 10s;
    .share_key = "123";

    .probe = {
        .request =
          "HEAD / HTTP/1.1"
          "Host: foo"
          "Connection: close";
        .window = 5;
        .threshold = 1;
        .timeout = 2s;
        .initial = 5;
        .dummy = true;
      }
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

#FASTLY recv

    # Require authentication for FASTLYPURGE requests
    if (req.request == "FASTLYPURGE") {
      set req.http.Fastly-Purge-Requires-Auth = "1";
    }

    if (req.request != "HEAD" && req.request != "GET" && req.request != "FASTLYPURGE") {
      return(pass);
    }

    return(lookup);
}

sub vcl_fetch {
#FASTLY fetch

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

  return(deliver);
}

sub vcl_hit {
#FASTLY hit

  if (!obj.cacheable) {
    return(pass);
  }
  return(deliver);
}

sub vcl_miss {
#FASTLY miss
  return(fetch);
}

sub vcl_deliver {
#FASTLY deliver
  return(deliver);
}

sub vcl_error {
#FASTLY error
}

sub vcl_pass {
#FASTLY pass
}

sub vcl_hash {

  #-FASTLY HASH CODE WITH GENERATION FOR PURGE ALL
  #

  #if unspecified fall back to normal
  {

    set req.hash += req.url;
    set req.hash += req.http.host;
    set req.hash += "#####GENERATION#####";
    return (hash);
  }
  #--FASTLY END HASH CODE

}

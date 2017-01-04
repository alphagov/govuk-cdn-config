backend dummy {
  .host = "127.0.0.1";
  .port = "1";
  .probe = {
    .request = "invalid";
    .initial = 0;
    .interval = 365d;
  }
}

sub vcl_recv {

  # Force SSL.
  if (!req.http.Fastly-SSL) {
    error 801 "Force SSL";
  } else {
    error 802 "Redirect GOV.UK";
  }

  return(error);
}

sub vcl_fetch {
}

sub vcl_hit {
}

sub vcl_miss {
}

sub vcl_deliver {
}

sub vcl_error {
  if (obj.status == 801) {
    set obj.status = 301;
    set obj.response = "Moved Permanently";
    set obj.http.Location = "https://" req.http.host req.url;
    set obj.http.Fastly-Backend-Name = "force_ssl";
  }

  if (obj.status == 802) {
    set obj.status = 302;
    set obj.response = "Moved Temporarily";
    set obj.http.Location = "https://www.gov.uk";
    set obj.http.Strict-Transport-Security = "max-age=63072000; includeSubDomains; preload";
  }

  synthetic {""};
  return (deliver);
}

sub vcl_pass {
}

sub vcl_hash {
}

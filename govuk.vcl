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
}

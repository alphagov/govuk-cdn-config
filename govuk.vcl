# TODO: Lots.

sub vcl_recv {
  # Unspoofable original client address.
  set req.http.True-Client-IP = req.http.Fastly-Client-IP;

#FASTLY recv
}

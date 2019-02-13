#!/bin/bash
set -eu

# Copy secret dictionaries over into /configs
rm -rf govuk-cdn-config-secrets
git clone git@github.com:alphagov/govuk-cdn-config-secrets.git

cp govuk-cdn-config-secrets/fastly/dictionaries/config/* configs/dictionaries
cp govuk-cdn-config-secrets/fastly/fastly.yaml .

bundle install --path "${HOME}/bundles/${JOB_NAME}"
bundle exec ./configure_dictionaries ${vhost} ${ENVIRONMENT}

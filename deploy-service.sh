#!/usr/bin/env bash

set -e

# Copy secrets over into /configs
rm -rf cdn-configs
git clone git@github.com:alphagov/cdn-configs.git

cp cdn-configs/fastly/fastly.yaml .

bundle install --path "${HOME}/bundles/${JOB_NAME}" --deployment
bundle exec ./configure_service ${vhost} ${ENVIRONMENT}

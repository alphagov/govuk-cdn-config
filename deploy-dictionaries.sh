#!/bin/bash
set -eu

# Copy secret dictionaries over into /configs
rm -rf cdn-configs
git clone git@github.com:alphagov/cdn-configs.git

cp cdn-configs/fastly/dictionaries/config/* configs/dictionaries
cp cdn-configs/fastly/fastly.yaml .

bundle install --path "${HOME}/bundles/${JOB_NAME}" --deployment
bundle exec ./configure_dictionaries ${vhost} ${ENVIRONMENT}

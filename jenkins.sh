#!/usr/bin/env bash

set -e

git clone 'git@github.com:alphagov/govuk-cdn-config-secrets.git'

cp govuk-cdn-config-secrets/fastly/fastly.yaml .

bundle install --path "${HOME}/bundles/${JOB_NAME}"
bundle exec ./deploy_vcl ${vhost} ${ENVIRONMENT}

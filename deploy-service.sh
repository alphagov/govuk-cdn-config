#!/bin/bash
set -eu

rm -rf govuk-cdn-config-secrets
git clone -b attempt_switch_assets_aws_staging git@github.com:alphagov/govuk-cdn-config-secrets.git

cp govuk-cdn-config-secrets/fastly/fastly.yaml .

bundle install --path "${HOME}/bundles/${JOB_NAME}" --deployment
bundle exec ./deploy_service ${vhost} ${ENVIRONMENT}

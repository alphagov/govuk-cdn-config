#!/bin/bash
set -eu

rm -rf govuk-cdn-config-secrets
git clone git@github.com:alphagov/govuk-cdn-config-secrets.git -b testing_copy_production

cp govuk-cdn-config-secrets/fastly/fastly.yaml .

bundle install --path "${HOME}/bundles/${JOB_NAME}" --deployment
bundle exec ./deploy_service ${vhost} ${ENVIRONMENT}

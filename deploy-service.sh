#!/usr/bin/env bash

set -e

git clone 'git@github.com:alphagov/cdn-configs.git'

cp cdn-configs/fastly/fastly.yaml .

bundle install --path "${HOME}/bundles/${JOB_NAME}" --deployment
bundle exec ./deploy_vcl ${vhost} ${ENVIRONMENT}

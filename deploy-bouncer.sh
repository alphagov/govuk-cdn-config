#!/bin/bash
set -eu

bundle install --path "${HOME}/bundles/${JOB_NAME}" --deployment
bundle exec ./deploy_bouncer

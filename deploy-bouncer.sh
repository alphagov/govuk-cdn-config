#!/bin/bash
set -e

bundle install --path "${HOME}/bundles/${JOB_NAME}" --deployment
bundle exec rake deploy:bouncer

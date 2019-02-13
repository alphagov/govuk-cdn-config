#!/bin/bash
set -eu

bundle install --path "${HOME}/bundles/${JOB_NAME}" --deployment
bundle exec ./configure_bouncer

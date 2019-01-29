#!/bin/bash
set -e

bundle install --path "${HOME}/bundles/${JOB_NAME}" --deployment
bundle exec ./configure_bouncer

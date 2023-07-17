# GOV.UK CDN config

Configuration for GOV.UK's content delivery network (CDN), [Fastly](https://fastly.com). It uses Fastly VCL (see [documentation](https://developer.fastly.com/reference/api/vcl-services/vcl/)). You can read more about [how GOV.UK CDN works](https://docs.publishing.service.gov.uk/manual/cdn.html) in the developer docs.

ℹ️ This repo has some [documented tech debt](https://trello.com/c/y6MIgxjp). It doesn't conform to GOV.UK standards.

## Deployment

You'll need to manually deploy your changes to all relevant environments, using the relevant script below.
Note that the `assets-eks` and `www-eks` VCL templates are no longer used.

After running the script, check the output to confirm that the differences between configurations are the expected ones.

### Deploy Service

Script: [deploy-service.sh](/deploy-service.sh)

Invoked via the [CDN: deploy service](https://deploy.blue.production.govuk.digital/job/Deploy_CDN) Jenkins job.

Requires: Fastly API token with `global` access to the service you're deploying (e.g. `Production GOV.UK` service).

This script allows you to deploy a new VCL on a number of Fastly services (see table below) and replaces the old configuration.

| service name | domain                           | Service name in Fastly             | description |
| ------------ | -------------------------------- | ---------------------------------- | ----------- |
| apt          | apt.publishing.service.gov.uk    | Production Apt                     | GOV.UK's Debian package repository |
| assets       | assets.publishing.service.gov.uk | Production Assets ±                | the GOV.UK domain for uploads and static assets |
| servicegovuk | service.gov.uk                   | Production service domain redirect | redirect from https://service.gov.uk to https://www.gov.uk |
| tldredirect  | gov.uk                           | Production TLD Redirect            | redirect from https://gov.uk to https://www.gov.uk |
| www          | www.gov.uk                       | Production GOV.UK ±                | the single government domain |

±  also has equivalents for Integration and Staging.

### Deploy Dictionaries

Script: [deploy-dictionaries.sh](/deploy-dictionaries.sh)

Invoked via the [CDN: update dictionaries](https://deploy.blue.production.govuk.digital/job/Update_CDN_Dictionaries) Jenkins job.

Requires: Fastly API token with `global` access to the service you're deploying (e.g. `Production GOV.UK` service).

Fastly provide a technology called [Edge Dictionaries](https://docs.fastly.com/guides/edge-dictionaries/)
which can be used to provide dynamic configuration to VCL. This script takes updates dictionaries defined in YAML files in [configs/dictionaries](/configs/dictionaries). We use it for [A/B testing](#ab-testing) and blocking IP addresses (the dictionary for this lives in [alphagov/govuk-cdn-config-secrets](https://github.com/alphagov/govuk-cdn-config-secrets/blob/master/fastly/dictionaries/config/ip_address_denylist.yaml) - read [more about IP banning](https://docs.publishing.service.gov.uk/manual/cdn.html#banning-ip-addresses-at-the-cdn-edge) in the docs).

### Deploy Bouncer

Script: [deploy-bouncer.sh](/deploy-bouncer.sh)

Invoked via the [CDN: deploy Bouncer configs](https://deploy.blue.production.govuk.digital/job/Bouncer_CDN/) Jenkins job.

Requires: Fastly API token with `global` access to "Staging Bouncer" or "Production Bouncer".

This configures the `bouncer` Fastly service with transitioned domains from Transition ([read about Transition here](https://docs.publishing.service.gov.uk/manual/transition-architecture.html)). The Jenkins job is not usually run manually - it's triggered by the [one of the transition Jenkins jobs](https://deploy.blue.production.govuk.digital/job/Transition_load_site_config). Read [more about the Fastly service](https://docs.publishing.service.gov.uk/manual/cdn.html#bouncer39s-fastly-service) in the developer docs.

## Making changes to VCL

You will need to re-generate the spec files when making changes to `www.vcl.erb`.

```sh
REGENERATE_EXPECTATIONS=1 bundle exec rspec
```

## A/B testing

We use edge dictionaries to define the configuration for A/B and multivariate tests. The same configuration applies to A/B and multivariate tests, differing only on the number of variants.

- `configs/dictionaries/active_ab_tests.yaml`: This controls whether the test is active or not. You may want to configure your test to be inactive at first, so that you can activate it at a later date.
- `configs/dictionaries/<test name lowercase>_percentages.yaml`: The percentage of users who should see the variants of your test. This can be changed at a later date to expand the test to more users, but note that there will be some lag because users who have already visited the site will stay in their variant test buckets until their cookie expires. (See `example_percentages.yaml`).
- `configs/dictionaries/ab_test_expiries.yaml`: The lifetime of the A/B test cookie. The value you choose depends on what kind of change you are making. If it is important that users always see a consistent version of the site (e.g. because you are making large changes to the navigation) then choose a lifetime which is significantly longer than the duration of your A/B test, such as 1 year. On the other hand, a shorter lifetime (such as 1 day) causes less lag when changing the B percentage, and might be more appropriate when testing something where consistency is less important from day-to-day, such as changing the order of search results.

## Licence

[MIT License](LICENCE)

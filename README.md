# GOV.UK CDN config

Configuration for GOV.UK's content delivery network (CDN).

Configures the [Fastly CDN](https://fastly.com) from version-controllable VCL and
YAML files, using Fastly's [API](https://docs.fastly.com/api/).

## Fastly dictionaries

Fastly provide a technology called [Edge Dictionaries](https://docs.fastly.com/guides/edge-dictionaries/)
which can be used to provide dynamic configuration to VCL.

## A/B and multivariate testing

We use edge dictionaries to define the configuration for A/B and multivariate tests. The same configuration applies to A/B and multivariate tests, differing only on the number of variants.

- `configs/dictionaries/active_ab_tests.yaml`: This controls whether the test is active or not. You may want to configure your test to be inactive at first, so that you can activate it at a later date.
- `configs/dictionaries/<test name lowercase>_percentages.yaml`: The percentage of users who should see the variants of your test. This can be changed at a later date to expand the test to more users, but note that there will be some lag because users who have already visited the site will stay in their variant test buckets until their cookie expires. (See `example_percentages.yaml`).
- `configs/dictionaries/ab_test_expiries.yaml`: The lifetime of the A/B test cookie. The value you choose depends on what kind of change you are making. If it is important that users always see a consistent version of the site (e.g. because you are making large changes to the navigation) then choose a lifetime which is significantly longer than the duration of your A/B test, such as 1 year. On the other hand, a shorter lifetime (such as 1 day) causes less lag when changing the B percentage, and might be more appropriate when testing something where consistency is less important from day-to-day, such as changing the order of search results.

## IP address blocking

We use an edge dictionary to block IP addresses, which lives in [alphagov/govuk-cdn-config-secrets](https://github.com/alphagov/govuk-cdn-config-secrets).

- `ip_address_blacklist.yaml`: This controls whether an IP address is blocked or not.

## Licence

[MIT License](LICENSE.MD)

# Fastly Compute@Edge test

This directory contains a definition for a Fastly [Compute@Edge](https://docs.fastly.com/products/compute-at-edge) service. The existing, VCL-based backend, is configured as a backend of this service.

The intention is to slowly migrate functionality from VCL to Compute@Edge, deploying both services in tandem after each change, and then remove the existing VCL backend once all the functionality has been migrated.

## Common tasks

- To run the test suite: `npm test`
- To start development server: `npm run serve`

## Deployment

- Install the [Fastly CLI](https://developer.fastly.com/reference/cli/)
- Create a Fastly API token with full access to the **Staging Compute@Edge Test** service (service ID `0yW7THGQHtorLIDxhrcWx4`)
- Create a Fastly CLI profile with `fastly profile create`, providing the API token you just generated
- Run `npm run deploy`

/// <reference types="@fastly/js-compute" />

addEventListener("fetch", (event) => event.respondWith(handleRequest(event)));

async function handleRequest(event: FetchEvent) {
  const url = new URL(event.request.url)
  Array.from(url.searchParams.keys())
    .filter(k => k.toLowerCase().startsWith("utm_"))
    .forEach(k => url.searchParams.delete(k))
  url.searchParams.sort()

  return fetch(new Request(url, event.request), { backend: "origin" })
}

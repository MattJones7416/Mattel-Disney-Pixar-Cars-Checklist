const API_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, If-None-Match",
  "Access-Control-Max-Age": "86400",
};

function json(data: unknown, status = 200): Response {
  return Response.json(data, {
    status,
    headers: {
      ...API_HEADERS,
      "Cache-Control": "no-store",
    },
  });
}

async function serveCatalogue(request: Request, env: Env): Promise<Response> {
  const assetURL = new URL(request.url);
  assetURL.pathname = "/catalog.json";
  assetURL.search = "";

  const asset = await env.ASSETS.fetch(new Request(assetURL, { method: "GET" }));
  if (!asset.ok) {
    console.error(JSON.stringify({
      event: "catalogue_asset_error",
      status: asset.status,
    }));
    return json({ error: "Catalogue unavailable" }, 503);
  }

  const headers = new Headers(asset.headers);
  for (const [name, value] of Object.entries(API_HEADERS)) {
    headers.set(name, value);
  }
  headers.set("Content-Type", "application/json; charset=utf-8");
  headers.set("Cache-Control", "public, max-age=900, stale-while-revalidate=86400");

  return new Response(request.method === "HEAD" ? null : asset.body, {
    status: asset.status,
    headers,
  });
}

export default {
  async fetch(request, env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: API_HEADERS });
    }

    if (url.pathname === "/health") {
      return json({
        status: "ok",
        service: "pixar-cars-catalog",
        catalogue: "/api/catalog",
      });
    }

    if (url.pathname === "/api/catalog") {
      if (request.method !== "GET" && request.method !== "HEAD") {
        return json({ error: "Method not allowed" }, 405);
      }
      return serveCatalogue(request, env);
    }

    return json({ error: "Not found" }, 404);
  },
} satisfies ExportedHandler<Env>;

// Netlify Function (v2) that serves the whole Fastify API.
//
// Netlify routes every path here (see `config.path`); each request is replayed
// into the Fastify app with `inject`, so routes, auth and error handling are
// identical to the standalone server. The app (and its Postgres pool) is built
// once per function instance and reused across invocations.
import type { FastifyInstance } from "fastify";
import { buildApp } from "../../src/create-app";

let appPromise: Promise<FastifyInstance> | null = null;

function getApp(): Promise<FastifyInstance> {
  appPromise ??= buildApp()
    .then(async (app) => {
      await app.ready();
      return app;
    })
    .catch((error) => {
      appPromise = null; // let the next request retry (e.g. database was down)
      throw error;
    });
  return appPromise;
}

const HOP_BY_HOP = new Set(["connection", "keep-alive", "transfer-encoding"]);

export default async function handler(request: Request): Promise<Response> {
  const app = await getApp();
  const url = new URL(request.url);

  const headers: Record<string, string> = {};
  request.headers.forEach((value, key) => {
    headers[key] = value;
  });

  const hasBody = request.method !== "GET" && request.method !== "HEAD";
  const body = hasBody ? Buffer.from(await request.arrayBuffer()) : undefined;

  const result = await app.inject({
    method: request.method as "GET",
    url: url.pathname + url.search,
    headers,
    payload: body && body.length > 0 ? body : undefined,
  });

  const responseHeaders = new Headers();
  for (const [key, value] of Object.entries(result.headers)) {
    if (value === undefined || HOP_BY_HOP.has(key.toLowerCase())) continue;
    if (Array.isArray(value)) {
      for (const item of value) responseHeaders.append(key, String(item));
    } else {
      responseHeaders.set(key, String(value));
    }
  }

  const noBody = request.method === "HEAD" || result.statusCode === 204 || result.statusCode === 304;
  return new Response(noBody ? null : new Uint8Array(result.rawPayload), {
    status: result.statusCode,
    headers: responseHeaders,
  });
}

export const config = {
  path: ["/", "/*"],
};

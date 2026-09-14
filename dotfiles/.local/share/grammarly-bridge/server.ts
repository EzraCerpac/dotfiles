const port = Number(Deno.env.get("PORT"));

if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error("PORT must be a valid TCP port");
}

const assetRoot = new URL("./", import.meta.url);
const drafts = new Map<string, string>();
const maxDraftBytes = 2 * 1024 * 1024;

const securityHeaders = {
  "cache-control": "no-store",
  "content-security-policy": [
    "default-src 'none'",
    "script-src 'self'",
    "style-src 'self'",
    "connect-src 'self'",
    "base-uri 'none'",
    "form-action 'none'",
    "frame-ancestors 'none'",
  ].join("; "),
  "referrer-policy": "no-referrer",
  "x-content-type-options": "nosniff",
  "x-frame-options": "DENY",
};

function response(body: BodyInit | null, init: ResponseInit = {}): Response {
  return new Response(body, {
    ...init,
    headers: { ...securityHeaders, ...init.headers },
  });
}

function tokenFrom(request: Request): string | undefined {
  const authorization = request.headers.get("authorization") ?? "";
  const match = authorization.match(/^Bearer ([a-f0-9]{64})$/);
  return match?.[1];
}

async function asset(name: string, contentType: string): Promise<Response> {
  try {
    const body = await Deno.readTextFile(new URL(name, assetRoot));
    return response(body, { headers: { "content-type": contentType } });
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) {
      return response("Not found\n", { status: 404 });
    }
    throw error;
  }
}

async function handler(request: Request): Promise<Response> {
  const url = new URL(request.url);

  if (request.method === "GET" && url.pathname === "/health") {
    return response(JSON.stringify({ ok: true, service: "grammarly-bridge" }), {
      headers: { "content-type": "application/json" },
    });
  }

  if (request.method === "GET" && url.pathname === "/") {
    return await asset("index.html", "text/html; charset=utf-8");
  }
  if (request.method === "GET" && url.pathname === "/app.js") {
    return await asset("app.js", "text/javascript; charset=utf-8");
  }
  if (request.method === "GET" && url.pathname === "/style.css") {
    return await asset("style.css", "text/css; charset=utf-8");
  }

  if (url.pathname !== "/api/draft") {
    return response("Not found\n", { status: 404 });
  }

  const token = tokenFrom(request);
  if (!token) {
    return response("Unauthorized\n", { status: 401 });
  }

  if (request.method === "PUT") {
    const contentLength = Number(request.headers.get("content-length") ?? "0");
    if (contentLength > maxDraftBytes) {
      return response("Draft too large\n", { status: 413 });
    }
    const text = await request.text();
    if (new TextEncoder().encode(text).byteLength > maxDraftBytes) {
      return response("Draft too large\n", { status: 413 });
    }
    drafts.set(token, text);
    return response(null, { status: 204 });
  }

  if (request.method === "GET") {
    const draft = drafts.get(token);
    if (draft === undefined) {
      return response("Draft not found\n", { status: 404 });
    }
    return response(draft, { headers: { "content-type": "text/plain; charset=utf-8" } });
  }

  if (request.method === "DELETE") {
    drafts.delete(token);
    return response(null, { status: 204 });
  }

  return response("Method not allowed\n", { status: 405 });
}

Deno.serve({ hostname: "127.0.0.1", port }, handler);

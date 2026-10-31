#!/usr/bin/env node
/**
 * Minimal OAuth (PKCE) flow against Cloudflare's dashboard, used instead of
 * `wrangler login` because wrangler rejects the callback when Cloudflare adds
 * extra query parameters (e.g. `scope`) to the redirect.
 *
 * Usage: node scripts/cf-oauth.mjs
 * Writes .cf-token.json (gitignored) with access_token / refresh_token.
 */
import http from "node:http";
import crypto from "node:crypto";
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, "..");

const CLIENT_ID = "54d11594-84e4-41aa-b438-e81b8fa78ee7";
const REDIRECT_URI = "http://localhost:8976/oauth/callback";
const SCOPE = [
  "offline_access",
  "account:read",
  "user:read",
  "workers:write",
  "workers_scripts:write",
  "d1:write",
].join(" ");

const verifier = crypto.randomBytes(48).toString("base64url");
const challenge = crypto.createHash("sha256").update(verifier).digest("base64url");
const state = crypto.randomBytes(12).toString("base64url");

const authUrl =
  "https://dash.cloudflare.com/oauth2/auth?" +
  new URLSearchParams({
    response_type: "code",
    client_id: CLIENT_ID,
    redirect_uri: REDIRECT_URI,
    scope: SCOPE,
    state,
    code_challenge: challenge,
    code_challenge_method: "S256",
  }).toString();

let finished = false;

async function exchange(code) {
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    client_id: CLIENT_ID,
    code,
    redirect_uri: REDIRECT_URI,
    code_verifier: verifier,
  });
  const response = await fetch("https://dash.cloudflare.com/oauth2/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body,
  });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`token exchange failed: HTTP ${response.status} ${text.slice(0, 300)}`);
  }
  return JSON.parse(text);
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, "http://localhost:8976");
  if (url.pathname !== "/oauth/callback") {
    res.writeHead(404).end("not found");
    return;
  }
  const code = url.searchParams.get("code");
  const gotState = url.searchParams.get("state");
  if (!code) {
    res.writeHead(400, { "content-type": "text/html; charset=utf-8" }).end("<h3>缺少 code</h3>");
    return;
  }
  if (gotState !== state) {
    res.writeHead(400, { "content-type": "text/html; charset=utf-8" }).end("<h3>state 不匹配，请重新生成链接</h3>");
    return;
  }

  try {
    const tokens = await exchange(code);
    writeFileSync(join(ROOT, ".cf-token.json"), JSON.stringify(tokens, null, 2), { mode: 0o600 });
    finished = true;
    res.writeHead(200, { "content-type": "text/html; charset=utf-8" }).end(
      "<meta name=viewport content='width=device-width'><h3>✅ 授权完成，可以回到对话了</h3>",
    );
    console.log("TOKEN_OK");
    setTimeout(() => process.exit(0), 300);
  } catch (error) {
    res.writeHead(500, { "content-type": "text/html; charset=utf-8" }).end("<h3>换取 token 失败</h3><pre>" + String(error) + "</pre>");
    console.error("TOKEN_ERR", error);
    setTimeout(() => process.exit(1), 300);
  }
});

server.listen(8976, "0.0.0.0", () => {
  console.log("AUTH_URL " + authUrl);
  console.log("waiting for callback on http://localhost:8976/oauth/callback ...");
});

setTimeout(() => {
  if (!finished) {
    console.error("TIMEOUT waiting for callback");
    process.exit(2);
  }
}, 10 * 60 * 1000);

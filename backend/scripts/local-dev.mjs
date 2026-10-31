#!/usr/bin/env node
/**
 * Local development server for the Worker without workerd.
 *
 * `wrangler dev` needs workerd, which requires a 48-bit virtual address space
 * and therefore cannot start inside some sandboxed/Android-based environments.
 * This script bundles the exact same Worker source with esbuild and runs it on
 * plain Node.js, backed by node:sqlite and a tiny D1 shim.
 *
 *   node scripts/local-dev.mjs [--port 8787] [--db .local/tgchat.db]
 */
import { DatabaseSync } from "node:sqlite";
import http from "node:http";
import { mkdirSync, readFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { pbkdf2Sync, randomBytes, randomUUID } from "node:crypto";
import { build } from "esbuild";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, "..");

function arg(name, fallback) {
  const idx = process.argv.indexOf(`--${name}`);
  return idx >= 0 ? process.argv[idx + 1] : fallback;
}

const PORT = Number(arg("port", process.env.PORT ?? 8787));
const DB_PATH = join(ROOT, arg("db", ".local/tgchat.db"));

mkdirSync(dirname(DB_PATH), { recursive: true });

// --------------------------------------------------------------------- sqlite
const sqlite = new DatabaseSync(DB_PATH);
sqlite.exec("PRAGMA journal_mode = WAL;");
sqlite.exec(readFileSync(join(ROOT, "schema.sql"), "utf8"));

class Statement {
  constructor(sql, args = []) {
    this.sql = sql;
    this.args = args;
  }
  bind(...args) {
    return new Statement(this.sql, args);
  }
  async first(column) {
    const row = sqlite.prepare(this.sql).get(...this.args);
    if (!row) return null;
    if (column) return row[column] ?? null;
    return row;
  }
  async all() {
    const rows = sqlite.prepare(this.sql).all(...this.args);
    return { results: rows, success: true, meta: { changes: 0 } };
  }
  async run() {
    const info = sqlite.prepare(this.sql).run(...this.args);
    return {
      success: true,
      meta: { changes: info.changes, last_row_id: Number(info.lastInsertRowid) },
    };
  }
}

const DB = {
  prepare: (sql) => new Statement(sql),
  batch: async (statements) => {
    const out = [];
    for (const statement of statements) out.push(await statement.run());
    return out;
  },
  exec: async (sql) => {
    sqlite.exec(sql);
    return { count: 1, duration: 0 };
  },
};

// ------------------------------------------------------------- durable object
const events = [];
const CHAT_HUB = {
  idFromName: (name) => ({ name }),
  get: (id) => ({
    fetch: async (input, init) => {
      const url = String(input);
      if (url.endsWith("/broadcast")) {
        events.push({ chatId: id.name, event: JSON.parse(init?.body ?? "{}") });
        if (events.length > 500) events.shift();
      }
      return new Response("ok");
    },
  }),
};

// ------------------------------------------------------------------ seeding
function seedAdmin() {
  const username = process.env.ADMIN_USERNAME ?? "admin";
  const password = process.env.ADMIN_PASSWORD ?? "admin12345";
  const existing = sqlite.prepare("SELECT id FROM users WHERE username = ?").get(username);
  if (existing) return;
  const iterations = 25_000;
  const salt = randomBytes(16);
  const hash = pbkdf2Sync(password, salt, iterations, 32, "sha256");
  const encoded = `pbkdf2$${iterations}$${salt.toString("hex")}$${hash.toString("hex")}`;
  sqlite
    .prepare(
      "INSERT INTO users (id, username, password_hash, display_name, avatar_color, role, created_at) VALUES (?,?,?,?,?,?,?)",
    )
    .run(randomUUID(), username, encoded, "Admin", "#3390EC", "admin", Date.now());
  console.log(`[seed] created admin account ${username} / ${password}`);
}

seedAdmin();

// ------------------------------------------------------------------- worker
const bundlePath = join(ROOT, ".local/worker.mjs");
await build({
  entryPoints: [join(ROOT, "src/index.ts")],
  bundle: true,
  format: "esm",
  platform: "neutral",
  target: ["es2022"],
  outfile: bundlePath,
  logLevel: "error",
});
const worker = (await import(pathToFileURL(bundlePath).href + `?v=${Date.now()}`)).default;

const ctx = {
  waitUntil: (promise) => {
    Promise.resolve(promise).catch(() => undefined);
  },
  passThroughOnException: () => undefined,
};
const env = { DB, CHAT_HUB, SESSION_TTL_DAYS: "30", PBKDF2_ITERATIONS: "100000" };

// ------------------------------------------------------------------- server
const server = http.createServer(async (req, res) => {
  try {
    if (req.url === "/__events") {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify(events));
      return;
    }

    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    const body = Buffer.concat(chunks);

    const headers = new Headers();
    for (const [key, value] of Object.entries(req.headers)) {
      if (typeof value === "string") headers.set(key, value);
    }

    const request = new Request(`http://127.0.0.1:${PORT}${req.url}`, {
      method: req.method,
      headers,
      body: req.method === "GET" || req.method === "HEAD" ? undefined : body,
    });

    const response = await worker.fetch(request, env, ctx);
    res.statusCode = response.status;
    response.headers.forEach((value, key) => {
      if (key.toLowerCase() !== "content-length") res.setHeader(key, value);
    });
    const buffer = Buffer.from(await response.arrayBuffer());
    res.end(buffer);
  } catch (error) {
    console.error("[local-dev]", error);
    res.statusCode = 500;
    res.end(JSON.stringify({ error: String(error) }));
  }
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`\n✅ tgchat backend (Node harness) listening on http://127.0.0.1:${PORT}`);
  console.log(`   database: ${DB_PATH}`);
  console.log(`   health:   http://127.0.0.1:${PORT}/api/health\n`);
});

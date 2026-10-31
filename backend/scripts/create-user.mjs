#!/usr/bin/env node
/**
 * Create a user in the D1 database.
 *
 *   node scripts/create-user.mjs --username alice --password secret123 \
 *        --name "Alice" --role user [--remote]
 *
 * Defaults to the *local* D1 database (used by `wrangler dev`). Pass --remote to
 * write to the production database.
 */
import { pbkdf2Sync, randomBytes, randomUUID } from "node:crypto";
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, "..");

const PALETTE = ["#3390EC", "#E17076", "#7BC862", "#E5CA77", "#A695E7", "#EE7AAE", "#6EC9CB", "#FAA774"];

function parseArgs(argv) {
  const out = { remote: false, role: "user", db: "tgchat" };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (!arg.startsWith("--")) continue;
    const key = arg.slice(2);
    if (key === "remote") {
      out.remote = true;
      continue;
    }
    const value = argv[i + 1];
    out[key] = value;
    i++;
  }
  return out;
}

function sqlQuote(value) {
  return "'" + String(value).replace(/'/g, "''") + "'";
}

export function hashPassword(password, iterations = Number(process.env.PBKDF2_ITERATIONS ?? 25000)) {
  const salt = randomBytes(16);
  const hash = pbkdf2Sync(password, salt, iterations, 32, "sha256");
  return `pbkdf2$${iterations}$${salt.toString("hex")}$${hash.toString("hex")}`;
}

export function runWrangler(args, { inherit = false } = {}) {
  const result = spawnSync("npx", ["wrangler", ...args], {
    cwd: ROOT,
    encoding: "utf8",
    stdio: inherit ? "inherit" : "pipe",
  });
  if (!inherit && result.status !== 0) {
    const output = (result.stdout ?? "") + (result.stderr ?? "");
    throw new Error(output.trim() || `wrangler exited with ${result.status}`);
  }
  return result;
}

export function createUserSql({ username, password, displayName, role }) {
  const id = randomUUID();
  const now = Date.now();
  const color = PALETTE[Math.floor(Math.random() * PALETTE.length)];
  const name = displayName?.trim() || username;
  return `INSERT INTO users (id, username, password_hash, display_name, avatar_color, role, created_at, last_seen_at)
VALUES (${sqlQuote(id)}, ${sqlQuote(username)}, ${sqlQuote(hashPassword(password))}, ${sqlQuote(name)}, ${sqlQuote(color)}, ${sqlQuote(role)}, ${now}, NULL);`;
}

function executeSql(sql, remote) {
  const dir = mkdtempSync(join(tmpdir(), "tgchat-"));
  const file = join(dir, "create-user.sql");
  writeFileSync(file, sql, "utf8");
  const args = ["d1", "execute", "tgchat", "--file", file];
  if (remote) args.push("--remote");
  else args.push("--local");
  return runWrangler(args, { inherit: true });
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.username || !args.password) {
    console.error("用法: node scripts/create-user.mjs --username <用户名> --password <密码> [--name 显示名] [--role admin|user] [--remote]");
    process.exit(1);
  }
  if (!/^[a-zA-Z0-9_.]{3,32}$/.test(args.username)) {
    console.error("用户名需为 3-32 位字母、数字、下划线或点");
    process.exit(1);
  }
  if (String(args.password).length < 6) {
    console.error("密码至少 6 位");
    process.exit(1);
  }
  if (args.role !== "admin" && args.role !== "user") {
    console.error("--role 只能是 admin 或 user");
    process.exit(1);
  }

  const sql = createUserSql({
    username: args.username,
    password: args.password,
    displayName: args.name,
    role: args.role,
  });

  console.log(`\n正在创建账号 ${args.username} (${args.role}) 到${args.remote ? "远程" : "本地"} D1 ...\n`);
  executeSql(sql, args.remote);
  console.log(`\n✅ 账号已创建：${args.username} / ${args.password}`);
}

if (process.argv[1] && process.argv[1].endsWith("create-user.mjs")) {
  main();
}

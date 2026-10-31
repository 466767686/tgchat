#!/usr/bin/env node
/**
 * One-shot Cloudflare setup:
 *   1. creates the D1 database (or reuses an existing one),
 *   2. writes its id into wrangler.toml,
 *   3. applies schema.sql to the remote database,
 *   4. optionally creates the first admin account.
 *
 * Usage:
 *   npx wrangler login          # once, if you have not logged in yet
 *   ADMIN_USERNAME=admin ADMIN_PASSWORD=yourpass npm run bootstrap
 */
import { spawnSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, "..");
const DB_NAME = "tgchat";

function wrangler(args, { capture = true } = {}) {
  const result = spawnSync("npx", ["wrangler", ...args], {
    cwd: ROOT,
    encoding: "utf8",
    stdio: capture ? "pipe" : "inherit",
  });
  return {
    status: result.status,
    output: `${result.stdout ?? ""}${result.stderr ?? ""}`,
  };
}

function findDatabaseId() {
  const list = wrangler(["d1", "list", "--json"]);
  if (list.status === 0) {
    try {
      const start = list.output.indexOf("[");
      const end = list.output.lastIndexOf("]");
      const parsed = JSON.parse(list.output.slice(start, end + 1));
      const hit = parsed.find((db) => db.name === DB_NAME);
      if (hit) return hit.uuid ?? hit.id ?? null;
    } catch {
      // fall through to create
    }
  }
  return null;
}

function main() {
  console.log("→ 检查 D1 数据库 ...");
  let databaseId = findDatabaseId();

  if (!databaseId) {
    console.log("→ 创建 D1 数据库 tgchat ...");
    const created = wrangler(["d1", "create", DB_NAME]);
    process.stdout.write(created.output);
    if (created.status !== 0 && !/already exists/i.test(created.output)) {
      console.error("创建 D1 数据库失败，请先执行 `npx wrangler login`。");
      process.exit(1);
    }
    const match = /database_id\s*=\s*"([^"]+)"/.exec(created.output);
    databaseId = match?.[1] ?? findDatabaseId();
  } else {
    console.log(`→ 复用已有数据库 ${DB_NAME} (${databaseId})`);
  }

  if (!databaseId) {
    console.error("无法获取 database_id，请手动把 `wrangler d1 create tgchat` 的输出填进 wrangler.toml。");
    process.exit(1);
  }

  console.log("→ 写入 wrangler.toml ...");
  const tomlPath = join(ROOT, "wrangler.toml");
  const toml = readFileSync(tomlPath, "utf8");
  writeFileSync(
    tomlPath,
    toml.replace(/database_id\s*=\s*"[^"]*"/, `database_id = "${databaseId}"`),
    "utf8",
  );

  console.log("→ 初始化表结构 ...");
  const schema = wrangler(["d1", "execute", DB_NAME, "--remote", "--file=./schema.sql"], { capture: false });
  if (schema.status !== 0) {
    console.error("建表失败。");
    process.exit(1);
  }

  const adminUser = process.env.ADMIN_USERNAME;
  const adminPass = process.env.ADMIN_PASSWORD;
  if (adminUser && adminPass) {
    console.log(`→ 创建管理员 ${adminUser} ...`);
    const result = spawnSync(
      process.execPath,
      [join(HERE, "create-user.mjs"), "--username", adminUser, "--password", adminPass, "--name", process.env.ADMIN_NAME ?? adminUser, "--role", "admin", "--remote"],
      { cwd: ROOT, stdio: "inherit" },
    );
    if (result.status !== 0) process.exit(result.status ?? 1);
  } else {
    console.log("（未设置 ADMIN_USERNAME / ADMIN_PASSWORD，跳过管理员创建）");
  }

  console.log("\n✅ 后端初始化完成。下一步：npx wrangler deploy");
}

main();

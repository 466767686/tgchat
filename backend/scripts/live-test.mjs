#!/usr/bin/env node
/**
 * End-to-end test against a *deployed* Worker, including the real WebSocket path.
 *
 *   ADMIN_PASSWORD=... node scripts/live-test.mjs https://tgchat-api.example.workers.dev
 */
const BASE = (process.argv[2] ?? "https://tgchat-api.doukuai798.workers.dev").replace(/\/$/, "");
const ADMIN_USER = process.env.ADMIN_USERNAME ?? "admin";
const ADMIN_PASS = process.env.ADMIN_PASSWORD ?? "";

let passed = 0;
let failed = 0;

function check(ok, label, extra = "") {
  if (ok) {
    passed++;
    console.log(`  ✅ ${label}`);
  } else {
    failed++;
    console.log(`  ❌ ${label}${extra ? ` — ${extra}` : ""}`);
  }
}

async function api(path, { method = "GET", token, body } = {}) {
  const headers = { accept: "application/json" };
  if (body !== undefined) headers["content-type"] = "application/json";
  if (token) headers.authorization = `Bearer ${token}`;
  const response = await fetch(BASE + path, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {}
  return { status: response.status, json, text };
}

function waitFor(predicate, timeoutMs, label) {
  return new Promise((resolve, reject) => {
    const started = Date.now();
    const timer = setInterval(() => {
      const value = predicate();
      if (value) {
        clearInterval(timer);
        resolve(value);
      } else if (Date.now() - started > timeoutMs) {
        clearInterval(timer);
        reject(new Error(`timeout: ${label}`));
      }
    }, 100);
  });
}

async function main() {
  console.log(`\nLive test → ${BASE}\n`);

  const health = await api("/api/health");
  check(health.status === 200 && health.json?.ok === true, "线上健康检查", health.text.slice(0, 120));

  const login = await api("/api/auth/login", {
    method: "POST",
    body: { username: ADMIN_USER, password: ADMIN_PASS },
  });
  check(login.status === 200 && !!login.json?.token, "线上管理员登录", login.text.slice(0, 160));
  if (!login.json?.token) throw new Error("cannot continue without admin token");
  const adminToken = login.json.token;

  const suffix = Date.now().toString(36).slice(-6);
  const username = `live_${suffix}`;
  const password = "live12345";
  const created = await api("/api/admin/users", {
    method: "POST",
    token: adminToken,
    body: { username, password, displayName: "Live Test" },
  });
  check(created.status === 201 && !!created.json?.user?.id, "线上建号", created.text.slice(0, 160));
  const chatId = created.json?.chatId;

  const userLogin = await api("/api/auth/login", { method: "POST", body: { username, password } });
  check(userLogin.status === 200 && !!userLogin.json?.token, "新账号登录");
  const userToken = userLogin.json.token;

  // ---- realtime: connect the new user's WebSocket, then have admin post a message
  const wsUrl = `${BASE.replace(/^http/, "ws")}/api/ws?chat=${chatId}&token=${userToken}`;
  const events = [];
  let wsOpen = false;
  const socket = new WebSocket(wsUrl);
  socket.addEventListener("open", () => {
    wsOpen = true;
  });
  socket.addEventListener("message", (event) => {
    try {
      events.push(JSON.parse(String(event.data)));
    } catch {}
  });

  try {
    await waitFor(() => wsOpen, 15000, "websocket open");
    check(true, "WebSocket 握手成功（Durable Object）");
  } catch (error) {
    check(false, "WebSocket 握手成功（Durable Object）", String(error.message));
  }

  const text = `realtime hello ${suffix}`;
  const sent = await api(`/api/chats/${chatId}/messages`, {
    method: "POST",
    token: adminToken,
    body: { text, clientId: `live-${suffix}` },
  });
  check(sent.status === 201 && sent.json?.message?.seq > 0, "管理员发送消息", sent.text.slice(0, 160));

  try {
    await waitFor(() => events.find((e) => e.type === "message" && e.message?.text === text), 12000, "realtime push");
    check(true, "消息通过 WebSocket 实时推送到对方");
  } catch (error) {
    check(false, "消息通过 WebSocket 实时推送到对方", `${String(error.message)}（收到 ${events.length} 个事件）`);
  }

  const history = await api(`/api/chats/${chatId}/messages?limit=50`, { token: userToken });
  check(
    history.json?.messages?.some((m) => m.text === text),
    "消息已落库，可拉取历史",
  );

  const read = await api(`/api/chats/${chatId}/read`, {
    method: "POST",
    token: userToken,
    body: { seq: sent.json?.message?.seq ?? 0 },
  });
  check(read.status === 200, "已读游标上报");

  // ---- typing event should reach the other member
  const typingBefore = events.length;
  socket.send(JSON.stringify({ type: "typing" }));

  // ---- bad token must be rejected
  const badSocket = new WebSocket(`${BASE.replace(/^http/, "ws")}/api/ws?chat=${chatId}&token=invalid`);
  const badClosed = await new Promise((resolve) => {
    const timer = setTimeout(() => resolve("timeout"), 8000);
    badSocket.addEventListener("error", () => {
      clearTimeout(timer);
      resolve("rejected");
    });
    badSocket.addEventListener("close", () => {
      clearTimeout(timer);
      resolve("rejected");
    });
    badSocket.addEventListener("open", () => {
      clearTimeout(timer);
      resolve("opened");
    });
  });
  check(badClosed === "rejected", "无效 token 的 WebSocket 被拒绝");

  socket.close();
  console.log(`\n结果：${passed} 通过，${failed} 失败\n`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});

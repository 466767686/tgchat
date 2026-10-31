import type { Env } from "./types";

export async function broadcast(
  env: Env,
  ctx: ExecutionContext,
  chatId: string,
  event: unknown,
  excludeUserId?: string,
): Promise<void> {
  const stub = env.CHAT_HUB.get(env.CHAT_HUB.idFromName(chatId));
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (excludeUserId) headers["x-exclude"] = excludeUserId;
  ctx.waitUntil(
    stub
      .fetch("https://hub/broadcast", { method: "POST", headers, body: JSON.stringify(event) })
      .catch(() => undefined),
  );
}

export interface Attachment {
  userId: string;
  name: string;
  color: string;
}

/**
 * One Durable Object instance per chat. Uses the WebSocket Hibernation API so
 * idle rooms cost nothing while still delivering messages instantly.
 */
export class ChatHub {
  constructor(private ctx: DurableObjectState, private env: Env) {}

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/broadcast") {
      const payload = await request.json();
      const exclude = request.headers.get("x-exclude") ?? undefined;
      this.broadcast(payload, exclude);
      return new Response("ok");
    }

    if (url.pathname === "/stats") {
      return Response.json({ sockets: this.ctx.getWebSockets().length });
    }

    const upgrade = request.headers.get("Upgrade");
    if (!upgrade || upgrade.toLowerCase() !== "websocket") {
      return new Response("Expected WebSocket upgrade", { status: 426 });
    }

    const userId = request.headers.get("x-user-id");
    const name = request.headers.get("x-user-name") ?? "";
    const color = request.headers.get("x-user-color") ?? "#3390EC";
    if (!userId) return new Response("Unauthorized", { status: 401 });

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair) as [WebSocket, WebSocket];

    this.ctx.acceptWebSocket(server);
    server.serializeAttachment({ userId, name, color } satisfies Attachment);

    return new Response(null, { status: 101, webSocket: client });
  }

  private broadcast(payload: unknown, excludeUserId?: string): void {
    const data = JSON.stringify(payload);
    for (const ws of this.ctx.getWebSockets()) {
      const att = ws.deserializeAttachment() as Attachment | null;
      if (excludeUserId && att?.userId === excludeUserId) continue;
      try {
        ws.send(data);
      } catch {
        // socket already gone; the runtime will clean it up
      }
    }
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    if (typeof message !== "string") return;
    let data: { type?: string };
    try {
      data = JSON.parse(message);
    } catch {
      return;
    }
    const att = ws.deserializeAttachment() as Attachment | null;
    if (!att) return;

    switch (data.type) {
      case "typing":
        this.broadcast({ type: "typing", userId: att.userId, name: att.name }, att.userId);
        break;
      case "ping":
        try {
          ws.send(JSON.stringify({ type: "pong", t: Date.now() }));
        } catch {
          /* ignore */
        }
        break;
      default:
        break;
    }
  }

  async webSocketClose(ws: WebSocket): Promise<void> {
    try {
      ws.close();
    } catch {
      /* ignore */
    }
  }

  async webSocketError(ws: WebSocket): Promise<void> {
    try {
      ws.close();
    } catch {
      /* ignore */
    }
  }
}

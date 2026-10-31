export interface Env {
  DB: D1Database;
  CHAT_HUB: DurableObjectNamespace;
  USER_HUB: DurableObjectNamespace;
  MEDIA: R2Bucket;
  SESSION_TTL_DAYS?: string;
  PBKDF2_ITERATIONS?: string;
}

export interface UserRow {
  id: string;
  username: string;
  password_hash: string;
  display_name: string;
  avatar_color: string;
  role: "admin" | "user";
  created_at: number;
  last_seen_at: number | null;
}

export interface PublicUser {
  id: string;
  username: string;
  displayName: string;
  avatarColor: string;
  role: string;
  lastSeenAt: number | null;
}

export function publicUser(u: UserRow): PublicUser {
  return {
    id: u.id,
    username: u.username,
    displayName: u.display_name,
    avatarColor: u.avatar_color,
    role: u.role,
    lastSeenAt: u.last_seen_at,
  };
}

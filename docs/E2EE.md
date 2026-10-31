# 端到端加密（E2EE）架构设计

> 状态：架构设计完成，客户端加密层尚未接入。当前所有消息在传输层使用 HTTPS/WSS 加密，
> 服务端（D1）以明文存储。本文描述计划采用的协议与数据结构，接入后旧聊天记录仍为明文。

## 1. 目标与威胁模型

- 服务端不可信：Cloudflare Worker、D1、R2、Durable Objects 都视为可能被读取。
- 防御：服务端只能看到密文、序号、时间戳、消息大小。
- 不防御：设备被控、截屏、对方主动泄露。

## 2. 密钥体系

| 密钥 | 算法 | 存储位置 |
| --- | --- | --- |
| 身份密钥 IK | Curve25519 | 设备 Keychain |
| 签名密钥 SPK | Ed25519 | 设备 Keychain |
| 一次性预共享密钥 OPK | X25519 | 设备 Keychain，公钥上传 |
| 会话根密钥 | HKDF-SHA256 | 内存 |
| 消息密钥链 | Double Ratchet | 内存 + 加密缓存 |

每台设备独立生成密钥对；`user_keys(user_id, device_id, ik_pub, spk_pub, opk_pub[], updated_at)` 存储在 D1，
私钥永不上传。

## 3. 私聊会话建立（X3DH）

1. A 拉取 B 的设备公钥包（IK/SPK/OPK）。
2. A 生成临时密钥 EK，计算共享密钥：
   `DH1 = DH(IK_A, SPK_B)`，`DH2 = DH(EK_A, IK_B)`，`DH3 = DH(EK_A, SPK_B)`，`DH4 = DH(EK_A, OPK_B)`。
3. `SK = HKDF(DH1 || DH2 || DH3 || DH4)`，作为 Double Ratchet 初始根密钥。
4. A 发送首条消息时附带 `ik_pub, ek_pub, opk_id, spk_sig`；B 用私钥复算 SK。

## 4. 消息加密（Double Ratchet）

- 每条消息：`AES-256-GCM(key=MK_n, nonce=random12, aad=chat_id||seq)`。
- 每次发送推进发送链，收到对方新公钥时推进接收链并做 DH ratchet。
- 序号 `seq` 由服务端分配，作为 AAD 一部分防止重放/重排。
- 服务端只存储：`ciphertext, nonce, sender_device, msg_type, seq, created_at`。

## 5. 群聊 / 频道（Sender Keys）

- 每个成员生成 Sender Key（32 字节）并用私聊 E2EE 分发给其他成员。
- 群消息用 Sender Key 的 AES-256-GCM 加密，附带 `sender_key_id`。
- 成员变动时轮换 Sender Key；新成员拿不到历史消息密钥（除非管理员主动导出）。

## 6. 媒体

- 客户端先随机生成 32 字节文件密钥，AES-256-GCM 分块加密。
- 密文上传 R2；`media_key` 与 `nonce` 随消息体一起加密传输。
- 服务端只看到加密块大小。

## 7. 多设备

- 每个设备一个 `device_id`，会话对每个设备单独建立（fan-out）。
- 新设备登录时不会自动获得旧会话密钥；可选择「同步最近消息」由用户输入恢复码。
- `GET /api/keys/:userId` 返回设备公钥列表，`POST /api/keys` 上传本设备公钥。

## 8. 安全码

- 双方对 `IK_A || IK_B` 做 SHA-256，取 60 位十进制显示，供线下比对。
- 密钥变化时客户端显示警告。

## 9. 服务端新增接口（计划）

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| POST | `/api/keys` | 上传设备公钥包 |
| GET | `/api/keys/:userId` | 拉取对方设备公钥列表 |
| POST | `/api/messages/:seq/key` | 群 Sender Key 分发（密文） |

## 10. 迁移步骤

1. 客户端实现密钥生成与 Keychain 存储。
2. 增加密钥上传/拉取接口与设备列表。
3. 私聊 X3DH + Double Ratchet 双端互通测试。
4. 群聊 Sender Keys。
5. 媒体加密与 R2 分块。
6. 旧明文消息标记 `encrypted=0`，新消息 `encrypted=1`，逐步淘汰明文。

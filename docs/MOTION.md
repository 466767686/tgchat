# Motion Design System

所有动效由 `ios/TgChat/Motion.swift` 统一治理，页面不再自写时长。

## Tokens

| Token | 值 | 用途 |
| --- | --- | --- |
| `Motion.quick` | spring 0.26 / 0.86 | 按钮按压、微交互 |
| `Motion.standard` | spring 0.36 / 0.87 | 默认布局、插入、面板 |
| `Motion.gentle` | spring 0.48 / 0.90 | 媒体、较大表面、滚动定位 |
| `Motion.bouncy` | spring 0.42 / 0.70 | 少量强调（发送、反应） |
| `Motion.fade` | easeOut 0.16 | 纯透明度切换 |
| `Motion.layout` | spring 0.34 / 0.88 | 列表重排、文件夹胶囊 |

`Motion.animation(token, reduceMotion:)` 在减少动态效果时统一降级为 `easeOut 0.15`。

## Reduce Motion 策略

- 位移过渡 → 纯透明度（`AnyTransition.motionSlide` 内部判断）
- 消息插入 → 淡入（`motionMessage`）
- 共享元素（文件夹胶囊、贴纸 Tab）→ 关闭 matchedGeometry，改为颜色过渡
- 图片查看器缩放 → 关闭，保留拖动（直接操作手势）
- 滚动定位 → 不使用动画（`withAnimation(nil)`）
- 数字键盘抖动 → 关闭，只保留错误文案与触感

## 组件

- `MotionPressStyle`：卡片/行按压（缩放 + 透明度），Reduce Motion 下只变透明度
- `MotionIconPressStyle`：图标按钮按压
- `AnyTransition.motionSlide / motionMessage / motionCrossfade`
- `Haptics.tap/selection/success`：与动效同步的触感反馈

## 主线程保护

| 热点 | 处理 |
| --- | --- |
| `formattedText`（Markdown + 链接 + @） | `TextFormatCache` NSCache，按原文缓存 |
| 气泡宽度测量（CoreText） | 按文本/引用/转发组合缓存 |
| 日期格式化 | 复用静态 `DateFormatter` |
| 远程图片 | `ImageCache` + 异步解码 |

## 使用约定

1. 新页面只使用 Motion token，不写裸 `spring`/`easeInOut`
2. 任何位移/缩放动画都必须经过 `reduceMotion` 分支
3. 动效不得阻塞操作：状态先变，动画跟随；不要用 `DispatchQueue` 延迟来"演"状态
4. 列表使用稳定 id（`message.id` / `chat.id`），避免身份变化导致重建
5. 共享元素只用于表达空间关系（文件夹、Tab、头像位），不做装饰

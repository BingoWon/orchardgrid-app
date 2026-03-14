<p align="center">
  <img src="https://orchardgrid.com/logo-with-text.svg" alt="OrchardGrid" height="80" />
</p>

<p align="center">
  <strong>随时随地共享 Apple Intelligence</strong>
</p>

<p align="center">
  把你的 Apple 设备变成分布式 AI 算力池。<br/>
  六项设备端 AI 能力，一套 OpenAI 兼容 API，无需云端 GPU。
</p>

<p align="center">
  <a href="https://apps.apple.com/us/app/orchardgrid/id6754092757">
    <img src="https://img.shields.io/badge/Download_on_the-App_Store-black?style=for-the-badge&logo=apple&logoColor=white" alt="App Store" />
  </a>
  <a href="https://orchardgrid.com">
    <img src="https://img.shields.io/badge/Website-orchardgrid.com-015135?style=for-the-badge" alt="Website" />
  </a>
  <a href="https://orchardgrid.com/docs">
    <img src="https://img.shields.io/badge/API_Docs-Reference-4A90D9?style=for-the-badge" alt="API Docs" />
  </a>
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/License-MIT-E4DFB8?style=for-the-badge" alt="MIT License" />
  </a>
</p>

<p align="center">
  <a href="README.md">English</a>
</p>

---

## 为什么做 OrchardGrid？

Apple Intelligence 只能在 Apple 设备的 Neural Engine 上运行，无法部署在传统云服务器上。OrchardGrid 把分散在世界各地的 Apple 设备组织成一个**统一的、可编程调用的 AI 算力池**，对外提供标准 API，任何兼容 OpenAI 的客户端都能直接调用。

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           API 调用方                                     │
│              (任意 OpenAI SDK / curl / HTTP 客户端)                       │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │ HTTP（OpenAI 兼容）
                               ▼
               ┌───────────────────────────────┐
               │     Cloudflare Workers         │
               │  ┌──────────────────────────┐  │
               │  │   Durable Object         │  │
               │  │   (DevicePoolManager)    │  │
               │  │                          │  │
               │  │  • 任务调度               │  │
               │  │  • 轮询 + 故障回避        │  │
               │  │  • 心跳监测               │  │
               │  │  • 流式转发               │  │
               │  └──────────────────────────┘  │
               │         ▲          ▲           │
               │   D1 (SQLite)   WebSocket      │
               │         │     Hibernation      │
               └─────────┼──────────┼───────────┘
                         │          │
              ┌──────────┘          └──────────────────┐
              ▼                                        ▼
   ┌─────────────────────┐                ┌─────────────────────┐
   │   Apple 设备 A       │                │   Apple 设备 B       │
   │   ┌───────────────┐  │                │   ┌───────────────┐  │
   │   │ 本地 API       │  │                │   │ 本地 API       │  │
   │   │ 服务器 (:8888) │  │                │   │ 服务器 (:8888) │  │
   │   └───────┬───────┘  │                │   └───────┬───────┘  │
   │           │           │                │           │           │
   │   ┌───────▼───────┐  │                │   ┌───────▼───────┐  │
   │   │  能力处理器     │  │                │   │  能力处理器     │  │
   │   │               │  │                │   │               │  │
   │   │ • Chat (LLM)  │  │                │   │ • Chat (LLM)  │  │
   │   │ • 图像生成     │  │                │   │ • 图像生成     │  │
   │   │ • NLP 分析     │  │                │   │ • NLP 分析     │  │
   │   │ • 视觉分析     │  │                │   │ • 视觉分析     │  │
   │   │ • 语音识别     │  │                │   │ • 语音识别     │  │
   │   │ • 声音分类     │  │                │   │ • 声音分类     │  │
   │   └───────────────┘  │                │   └───────────────┘  │
   └─────────────────────┘                └─────────────────────┘
```

## AI 能力

OrchardGrid 通过统一 API 暴露 **六项** Apple 设备端 AI 能力：

| 能力 | Apple 框架 | API 端点 | 说明 |
|------|-----------|---------|------|
| **Chat** | FoundationModels | `POST /v1/chat/completions` | LLM 文本生成，支持流式和结构化输出 |
| **图像生成** | ImagePlayground | `POST /v1/images/generations` | 文字生图（插画、素描风格） |
| **NLP** | NaturalLanguage | `POST /v1/nlp/analyze` | 语言检测、实体识别、分词、嵌入向量 |
| **视觉** | Vision | `POST /v1/vision/analyze` | OCR、图像分类、人脸检测、条码识别 |
| **语音** | Speech | `POST /v1/audio/transcriptions` | 语音转文字，支持 50+ 种语言 |
| **声音** | SoundAnalysis | `POST /v1/audio/classify` | 环境声音分类（约 300 种类别） |

每项能力都可以通过**本地直连 API**（局域网内）和**云端中继**（全球任意位置）两种方式访问。

## 核心特性

- **OpenAI 兼容** — 直接替换 OpenAI SDK 的后端地址即可使用，客户端零改动
- **双通道访问** — 本地 8888 端口直连，或通过 Cloudflare Workers 云端中继
- **流式响应** — 基于 Server-Sent Events 的实时文本输出
- **结构化输出** — 完整支持 JSON Schema，确保响应格式的确定性
- **能力开关** — 在 app 界面中独立开关每项能力
- **容错设备池** — 支持故障时间衰减的轮询调度算法，自动回避异常设备
- **隐私优先** — 所有 AI 推理在设备本地完成，云端中继仅做任务路由，不存储任何数据

## 系统架构

### 反向推理

传统 AI 服务的 GPU 在服务端，而 OrchardGrid 的服务端（Cloudflare Worker）**没有任何算力**，只是一个调度器。真正的推理发生在用户的 Apple 设备上，这些设备通常在 NAT 和防火墙之后。

这种"反向推理"模式要求设备侧使用 **WebSocket** 长连接——服务端通过已建立的连接主动推送任务，设备处理后通过同一连接回传结果。对外的 API 侧则保持标准 **HTTP**，完全兼容 OpenAI。

### 双层协议设计

| 层 | 协议 | 用途 |
|---|------|------|
| 对外（API 调用方） | HTTP REST + SSE | OpenAI 兼容 API，对调用方完全透明 |
| 对内（Apple 设备） | WebSocket | 持久双向连接，用于任务下发、结果回传和心跳探活 |

### 原生 App 架构

```
orchardgrid-app/
├── App/                    # 入口、生命周期管理
├── Core/
│   ├── Models/             # 共享类型：Capability、Device、Task
│   ├── Services/
│   │   ├── APIServer        # 本地 HTTP 服务器（NWListener，端口 8888）
│   │   ├── WebSocketClient  # 云端连接，按能力分发任务
│   │   ├── SharingManager   # 统筹本地和云端共享，管理能力开关
│   │   ├── LLMProcessor     # FoundationModels 集成
│   │   ├── ImageProcessor   # ImagePlayground 集成
│   │   └── Processors/      # NLP、Vision、Speech、Sound 处理器
│   └── Utilities/           # 配置、日志、设备信息、网络信息
├── Features/               # 功能模块（MVVM）
│   ├── Auth/                # 基于 Clerk 的认证
│   ├── Chat/                # 内置聊天界面，支持 Markdown 渲染
│   ├── Devices/             # 设备管理、能力卡片
│   ├── APIKeys/             # API 密钥管理
│   └── Logs/                # 任务历史查看
└── UI/                     # 共享组件、导航
```

### 云端 Worker 架构

后端运行在 Cloudflare Workers 上，以 **Durable Object**（DevicePoolManager）作为有状态的调度核心：

- **任务调度** — 按能力感知的轮询设备选择
- **故障恢复** — 带时间衰减的失败计数 + 兜底选择策略
- **流式转发** — WebSocket 与 HTTP SSE 之间的实时中继
- **WebSocket Hibernation** — 空闲连接几乎零成本
- **D1 数据库** — 设备注册表、任务历史、API 密钥管理

## 系统要求

| | 最低版本 |
|---|---------|
| **macOS** | 26.0+（Tahoe） |
| **iOS / iPadOS** | 26.0+ |
| **芯片** | Apple Silicon（M1+ / A17 Pro+） |
| **Apple Intelligence** | 已开启且模型已下载 |
| **Xcode** | 26.0+（仅源码构建需要） |

## 快速开始

### 从 App Store 安装

<a href="https://apps.apple.com/us/app/orchardgrid/id6754092757">
  <img src="https://img.shields.io/badge/Download_on_the-App_Store-black?style=for-the-badge&logo=apple&logoColor=white" alt="App Store" />
</a>

### 从源码构建

```bash
git clone https://github.com/BingoWon/orchardgrid-app.git
cd orchardgrid-app
open orchardgrid-app.xcodeproj
# 构建运行 (Cmd+R)
```

### 快速测试

App 启动后，本地 API 服务器自动在 8888 端口运行：

```bash
# 文本对话
curl http://localhost:8888/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"apple-intelligence","messages":[{"role":"user","content":"你好！"}]}'

# 查看可用模型
curl http://localhost:8888/v1/models
```

### 云端共享

1. 在 app 中登录你的 Apple 账号
2. 开启"共享到云端"——设备会通过 WebSocket 连接到 OrchardGrid 的中继服务
3. 在 [控制台](https://orchardgrid.com/dashboard/api-keys) 创建 API 密钥
4. 从全球任意位置调用：

```bash
curl https://orchardgrid.com/v1/chat/completions \
  -H "Authorization: Bearer 你的API密钥" \
  -H "Content-Type: application/json" \
  -d '{"model":"apple-intelligence","messages":[{"role":"user","content":"你好！"}]}'
```

## API 端点

| 方法 | 路径 | 能力 |
|------|------|------|
| `GET` | `/v1/models` | 列出可用模型 |
| `POST` | `/v1/chat/completions` | 文本对话（支持流式） |
| `POST` | `/v1/images/generations` | 图像生成 |
| `POST` | `/v1/nlp/analyze` | NLP 分析 |
| `POST` | `/v1/vision/analyze` | 视觉分析 |
| `POST` | `/v1/audio/transcriptions` | 语音转文字 |
| `POST` | `/v1/audio/classify` | 声音分类 |

完整的交互式 API 文档：[orchardgrid.com/docs](https://orchardgrid.com/docs)

## 技术栈

| 层 | 技术 |
|---|------|
| 语言 | Swift 6，严格并发模式 |
| UI | SwiftUI |
| 网络 | Apple Network 框架（NWListener / NWConnection） |
| AI 框架 | FoundationModels、ImagePlayground、NaturalLanguage、Vision、Speech、SoundAnalysis |
| 云端后端 | Cloudflare Workers + Durable Objects + D1 |
| 认证 | Clerk（Apple 登录、JWT） |
| 前端 | React 19 + Vite + TailwindCSS |

## 隐私

- **设备端推理** — 所有 AI 处理在 Apple Neural Engine 上本地完成
- **零数据存储** — 云端中继仅做任务路由，不存储任何内容
- **无数据采集** — 不收集任何个人数据或 AI 请求内容
- **开源透明** — 代码完全公开，欢迎审计

## 关联仓库

| 仓库 | 说明 |
|------|------|
| [orchardgrid](https://github.com/BingoWon/orchardgrid) | 云端 Worker、Web 控制台和产品官网 |
| orchardgrid-app（本仓库） | Apple 原生应用（macOS / iOS / iPadOS） |

## 参与贡献

欢迎提交 Pull Request！

1. Fork 本仓库
2. 创建功能分支 (`git checkout -b feature/amazing-feature`)
3. 提交改动 (`git commit -m 'Add amazing feature'`)
4. 推送分支 (`git push origin feature/amazing-feature`)
5. 发起 Pull Request

## 许可证

本项目基于 MIT 许可证开源，详见 [LICENSE](LICENSE)。

---

<p align="center">
  <a href="https://orchardgrid.com">官网</a> &nbsp;·&nbsp;
  <a href="https://orchardgrid.com/docs">API 文档</a> &nbsp;·&nbsp;
  <a href="https://apps.apple.com/us/app/orchardgrid/id6754092757">App Store</a> &nbsp;·&nbsp;
  <a href="https://orchardgrid.com/dashboard">控制台</a>
</p>

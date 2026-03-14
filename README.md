<p align="center">
  <img src="https://orchardgrid.com/logo-with-text.svg" alt="OrchardGrid" height="80" />
</p>

<p align="center">
  <strong>Share Apple Intelligence Anywhere</strong>
</p>

<p align="center">
  Turn your Apple devices into a distributed AI compute pool.<br/>
  Six on-device capabilities. One OpenAI-compatible API. Zero cloud GPUs.
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
  <a href="README.zh-CN.md">中文文档</a>
</p>

---

## Why OrchardGrid?

Apple Intelligence runs exclusively on Apple's Neural Engine — it can't be deployed on traditional cloud servers. OrchardGrid bridges this gap by organizing Apple devices worldwide into a **unified, programmable AI compute pool**, exposing their capabilities through a standard API that any OpenAI-compatible client can call directly.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         API Consumers                                   │
│              (Any OpenAI SDK / curl / HTTP client)                       │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │ HTTP (OpenAI-compatible)
                               ▼
               ┌───────────────────────────────┐
               │     Cloudflare Workers         │
               │  ┌──────────────────────────┐  │
               │  │   Durable Object         │  │
               │  │   (DevicePoolManager)    │  │
               │  │                          │  │
               │  │  • Task scheduling       │  │
               │  │  • Round-robin + failover│  │
               │  │  • Heartbeat monitoring  │  │
               │  │  • Stream relay          │  │
               │  └──────────────────────────┘  │
               │         ▲          ▲           │
               │   D1 (SQLite)   WebSocket      │
               │         │     Hibernation      │
               └─────────┼──────────┼───────────┘
                         │          │
              ┌──────────┘          └──────────────────┐
              ▼                                        ▼
   ┌─────────────────────┐                ┌─────────────────────┐
   │   Apple Device A     │                │   Apple Device B     │
   │   ┌───────────────┐  │                │   ┌───────────────┐  │
   │   │ Local API      │  │                │   │ Local API      │  │
   │   │ Server (:8888) │  │                │   │ Server (:8888) │  │
   │   └───────┬───────┘  │                │   └───────┬───────┘  │
   │           │           │                │           │           │
   │   ┌───────▼───────┐  │                │   ┌───────▼───────┐  │
   │   │  Capability    │  │                │   │  Capability    │  │
   │   │  Processors    │  │                │   │  Processors    │  │
   │   │               │  │                │   │               │  │
   │   │ • Chat (LLM)  │  │                │   │ • Chat (LLM)  │  │
   │   │ • Image Gen   │  │                │   │ • Image Gen   │  │
   │   │ • NLP         │  │                │   │ • NLP         │  │
   │   │ • Vision      │  │                │   │ • Vision      │  │
   │   │ • Speech      │  │                │   │ • Speech      │  │
   │   │ • Sound       │  │                │   │ • Sound       │  │
   │   └───────────────┘  │                │   └───────────────┘  │
   └─────────────────────┘                └─────────────────────┘
```

## Capabilities

OrchardGrid exposes **six** Apple on-device AI capabilities through a unified API:

| Capability | Framework | API Endpoint | Description |
|------------|-----------|-------------|-------------|
| **Chat** | FoundationModels | `POST /v1/chat/completions` | LLM text generation with streaming & structured output |
| **Image** | ImagePlayground | `POST /v1/images/generations` | Text-to-image generation (illustration, sketch) |
| **NLP** | NaturalLanguage | `POST /v1/nlp/analyze` | Language detection, NER, tokenization, embeddings |
| **Vision** | Vision | `POST /v1/vision/analyze` | OCR, image classification, face & barcode detection |
| **Speech** | Speech | `POST /v1/audio/transcriptions` | Speech-to-text in 50+ languages |
| **Sound** | SoundAnalysis | `POST /v1/audio/classify` | Environmental sound classification (~300 categories) |

Every capability is available both through the **local direct API** (on your LAN) and the **cloud relay** (from anywhere).

## Key Features

- **OpenAI-compatible** — Drop-in replacement for OpenAI SDK. No client-side changes needed.
- **Dual access modes** — Direct local API on port 8888, or cloud relay via Cloudflare Workers.
- **Streaming** — Server-Sent Events for real-time chat responses.
- **Structured output** — Full JSON Schema support for deterministic response formatting.
- **Per-capability toggles** — Enable or disable each capability individually from the app UI.
- **Fault-tolerant device pool** — Round-robin scheduling with time-decayed failure avoidance across the device pool.
- **Privacy-first** — All AI inference happens on-device. The cloud relay is a pure task router with zero data storage.

## Architecture

### Reverse Inference

Unlike traditional AI services where the server owns the GPU, OrchardGrid's server (Cloudflare Worker) has **zero compute**. It acts purely as a coordinator. The actual inference happens on user-owned Apple devices behind NATs and firewalls.

This "reverse inference" pattern requires **WebSocket** for the internal device-facing protocol — the server must push tasks to devices, and devices must stream results back, all through a single persistent connection. The external API-facing protocol remains standard **HTTP**, fully OpenAI-compatible.

### Two-Layer Protocol Design

| Layer | Protocol | Purpose |
|-------|----------|---------|
| External (API consumers) | HTTP REST + SSE | OpenAI-compatible API, transparent to clients |
| Internal (Apple devices) | WebSocket | Persistent bidirectional connection for task dispatch, result relay, and heartbeat |

### Native App Architecture

```
orchardgrid-app/
├── App/                    # Entry point, lifecycle management
├── Core/
│   ├── Models/             # Shared types: Capability, Device, Task
│   ├── Services/
│   │   ├── APIServer        # Local HTTP server (NWListener, port 8888)
│   │   ├── WebSocketClient  # Cloud connection, capability-based task dispatch
│   │   ├── SharingManager   # Orchestrates local + cloud sharing, capability toggles
│   │   ├── LLMProcessor     # FoundationModels integration
│   │   ├── ImageProcessor   # ImagePlayground integration
│   │   └── Processors/      # NLP, Vision, Speech, Sound processors
│   └── Utilities/           # Config, logging, device info, network info
├── Features/               # Feature modules (MVVM)
│   ├── Auth/                # Clerk-based authentication
│   ├── Chat/                # Built-in chat UI with markdown rendering
│   ├── Devices/             # Device management, capability cards
│   ├── APIKeys/             # API key management
│   └── Logs/                # Task history viewer
└── UI/                     # Shared components, navigation
```

### Cloud Worker Architecture

The backend runs on Cloudflare Workers with a **Durable Object** (DevicePoolManager) as the stateful coordination hub:

- **Task scheduling** — Capability-aware round-robin device selection
- **Failure recovery** — Time-decayed failure counts with fallback selection
- **Stream relay** — Real-time SSE relay between WebSocket and HTTP
- **WebSocket Hibernation** — Near-zero cost for idle device connections
- **D1 database** — Device registry, task history, API key management

## Requirements

| | Minimum |
|---|---------|
| **macOS** | 26.0+ (Tahoe) |
| **iOS / iPadOS** | 26.0+ |
| **Chip** | Apple Silicon (M1+ / A17 Pro+) |
| **Apple Intelligence** | Enabled with model downloaded |
| **Xcode** | 26.0+ (for building from source) |

## Getting Started

### Install from App Store

<a href="https://apps.apple.com/us/app/orchardgrid/id6754092757">
  <img src="https://img.shields.io/badge/Download_on_the-App_Store-black?style=for-the-badge&logo=apple&logoColor=white" alt="App Store" />
</a>

### Build from Source

```bash
git clone https://github.com/BingoWon/orchardgrid-app.git
cd orchardgrid-app
open orchardgrid-app.xcodeproj
# Build & Run (Cmd+R)
```

### Quick Test

Once the app is running, the local API server starts automatically on port 8888:

```bash
# Chat completion
curl http://localhost:8888/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"apple-intelligence","messages":[{"role":"user","content":"Hello!"}]}'

# List available models
curl http://localhost:8888/v1/models
```

### Cloud Sharing

1. Sign in with your Apple account in the app
2. Enable "Share to Cloud" — the device connects to OrchardGrid's relay via WebSocket
3. Generate an API key from the [dashboard](https://orchardgrid.com/dashboard/api-keys)
4. Use the cloud endpoint from anywhere:

```bash
curl https://orchardgrid.com/v1/chat/completions \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"apple-intelligence","messages":[{"role":"user","content":"Hello!"}]}'
```

## API Endpoints

| Method | Endpoint | Capability |
|--------|----------|------------|
| `GET` | `/v1/models` | List available models |
| `POST` | `/v1/chat/completions` | Chat (supports streaming) |
| `POST` | `/v1/images/generations` | Image generation |
| `POST` | `/v1/nlp/analyze` | NLP analysis |
| `POST` | `/v1/vision/analyze` | Vision analysis |
| `POST` | `/v1/audio/transcriptions` | Speech-to-text |
| `POST` | `/v1/audio/classify` | Sound classification |

Full interactive API reference: [orchardgrid.com/docs](https://orchardgrid.com/docs)

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Swift 6 with strict concurrency |
| UI | SwiftUI |
| Networking | Apple Network framework (NWListener / NWConnection) |
| AI Frameworks | FoundationModels, ImagePlayground, NaturalLanguage, Vision, Speech, SoundAnalysis |
| Cloud Backend | Cloudflare Workers + Durable Objects + D1 |
| Auth | Clerk (Apple Sign-In, JWT) |
| Frontend | React 19 + Vite + TailwindCSS |

## Privacy

- **On-device inference** — All AI processing runs locally on the Apple Neural Engine
- **Zero data storage** — The cloud relay routes tasks without storing any content
- **No telemetry** — No personal data or AI queries are collected
- **Open source** — Full transparency, audit the code yourself

## Related Repositories

| Repository | Description |
|------------|-------------|
| [orchardgrid](https://github.com/BingoWon/orchardgrid) | Cloud worker, web dashboard, and landing page |
| orchardgrid-app (this repo) | Native Apple app (macOS / iOS / iPadOS) |

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

<p align="center">
  <a href="https://orchardgrid.com">Website</a> &nbsp;·&nbsp;
  <a href="https://orchardgrid.com/docs">API Docs</a> &nbsp;·&nbsp;
  <a href="https://apps.apple.com/us/app/orchardgrid/id6754092757">App Store</a> &nbsp;·&nbsp;
  <a href="https://orchardgrid.com/dashboard">Dashboard</a>
</p>

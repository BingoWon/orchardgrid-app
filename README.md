<p align="center">
  <img src="https://orchardgrid.com/logo-with-text.svg" alt="OrchardGrid" height="80" />
</p>

<p align="center">
  <strong>Share Apple Intelligence Anywhere You Want</strong>
</p>

<p align="center">
  Transform your Apple devices into an AI API server.<br/>
  OpenAI-compatible interface, privacy-first architecture, completely free and open source.
</p>

<p align="center">
  <a href="https://apps.apple.com/us/app/orchardgrid/id6754092757">
    <img src="https://img.shields.io/badge/Download_on_the-App_Store-black?style=for-the-badge&logo=apple&logoColor=white" alt="App Store" />
  </a>
  <a href="https://orchardgrid.com">
    <img src="https://img.shields.io/badge/Website-orchardgrid.com-015135?style=for-the-badge" alt="Website" />
  </a>
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/License-MIT-E4DFB8?style=for-the-badge" alt="MIT License" />
  </a>
</p>

---

## ✨ Features

- **OpenAI API Compatible** — Drop-in replacement for OpenAI API, works with any OpenAI client
- **Two Sharing Modes** — Share locally on your network or remotely via cloud relay
- **Structured Output** — Full JSON Schema support with runtime validation
- **Streaming Support** — Server-Sent Events (SSE) for real-time responses
- **Multi-turn Conversations** — Stateful session management
- **Privacy First** — All AI processing happens on your device
- **Cross-Platform** — Native apps for iOS, iPadOS, and macOS
- **Completely Free** — No subscriptions, no hidden costs, open source

## 📋 Requirements

- **macOS 26.0+** / **iOS 26.0+** / **iPadOS 26.0+**
- Apple Silicon (M-series chips) with Neural Engine
- Apple Intelligence enabled on your device
- Xcode 26.0+ (for development)

## 📲 Installation

### App Store (Recommended)

Download OrchardGrid from the [App Store](https://apps.apple.com/us/app/orchardgrid/id6754092757).

### Build from Source

```bash
# Clone the repository
git clone https://github.com/BingoWon/orchardgrid-app.git
cd orchardgrid-app

# Open in Xcode
open OrchardGrid.xcodeproj

# Build and Run (Cmd+R)
```

## 🌐 Sharing Modes

OrchardGrid offers two ways to share your Apple Intelligence API:

### Share Locally

Share within your local network. Perfect for home or office use where all devices are on the same WiFi/LAN.

| Property | Value |
|----------|-------|
| **Endpoint** | `http://<local-ip>:8080/v1` |
| **Access** | Same network only |
| **Latency** | Lowest (direct connection) |
| **Privacy** | Maximum (data stays on LAN) |
| **Requirements** | Devices on same network |

```bash
# Find your local IP
ipconfig getifaddr en0  # macOS WiFi

# Example endpoint
http://192.168.1.100:8080/v1/chat/completions
```

### Share to Cloud

Share via OrchardGrid's cloud relay service. Access your AI API from anywhere in the world.

| Property | Value |
|----------|-------|
| **Endpoint** | `https://api.orchardgrid.com/v1` |
| **Access** | Anywhere with internet |
| **Latency** | Higher (relayed connection) |
| **Privacy** | High (E2E encrypted, no data stored) |
| **Requirements** | OrchardGrid account, API key |

```bash
# Example endpoint (with your API key)
curl -X POST https://api.orchardgrid.com/v1/chat/completions \
  -H "Authorization: Bearer og_your_api_key" \
  -H "Content-Type: application/json" \
  -d '{"model": "apple-intelligence", "messages": [{"role": "user", "content": "Hello!"}]}'
```

> **Note:** Cloud sharing requires signing in to your OrchardGrid account and generating an API key from the [dashboard](https://orchardgrid.com/dashboard).

## 📖 API Reference

### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/v1/chat/completions` | Create a chat completion |
| `GET` | `/v1/models` | List available models |

### Chat Completions

**Request:**

```json
{
  "model": "apple-intelligence",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "Hello!"}
  ],
  "stream": false,
  "response_format": {
    "type": "json_schema",
    "json_schema": { ... }
  }
}
```

**Response:**

```json
{
  "id": "chatcmpl-xxxxx",
  "object": "chat.completion",
  "created": 1234567890,
  "model": "apple-intelligence",
  "choices": [{
    "index": 0,
    "message": {
      "role": "assistant",
      "content": "Hello! How can I help you today?"
    },
    "finish_reason": "stop"
  }],
  "usage": {
    "prompt_tokens": 0,
    "completion_tokens": 0,
    "total_tokens": 0
  }
}
```

### Streaming

Enable streaming responses with Server-Sent Events:

```bash
curl -N -X POST http://192.168.1.100:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "apple-intelligence",
    "messages": [{"role": "user", "content": "Count from 1 to 10"}],
    "stream": true
  }'
```

### Structured Output

Generate structured JSON responses with schema validation:

```bash
curl -X POST http://192.168.1.100:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "apple-intelligence",
    "messages": [
      {"role": "user", "content": "Generate a person named Alice, age 28"}
    ],
    "response_format": {
      "type": "json_schema",
      "json_schema": {
        "name": "Person",
        "strict": true,
        "schema": {
          "type": "object",
          "properties": {
            "name": {"type": "string"},
            "age": {"type": "integer"}
          },
          "required": ["name", "age"],
          "additionalProperties": false
        }
      }
    }
  }'
```

## 🔧 Supported JSON Schema Features

### Types

| Type | Description |
|------|-------------|
| `string` | Text values |
| `integer` | Whole numbers |
| `number` | Decimal numbers |
| `boolean` | true/false values |
| `array` | Lists of values |
| `object` | Nested structures |
| `enum` | Enumerated values (via anyOf) |

### Constraints

- `minimum` / `maximum` — Numeric bounds
- `minItems` / `maxItems` — Array length bounds
- `required` — Required fields
- `additionalProperties` — Strict mode

### Advanced Features

- Nested objects (multi-level)
- Arrays of objects
- Optional fields
- Enum constraints
- Schema references

## 🏗️ Architecture

```
OrchardGrid/
├── OrchardGrid/
│   ├── App/
│   │   └── OrchardGridApp.swift      # Application entry point
│   ├── Core/
│   │   ├── APIServer.swift           # HTTP server & OpenAI API layer
│   │   └── SchemaConverter.swift     # JSON Schema → DynamicGenerationSchema
│   ├── Views/
│   │   ├── MainView.swift            # Main interface
│   │   └── ServerStatusView.swift    # Server status & monitoring
│   └── Resources/
│       └── Assets.xcassets           # App icons & images
├── Tests/
│   ├── schemas/                      # JSON Schema test files
│   └── test_structured_output.py     # Python test suite
└── README.md
```

### Technical Stack

- **Language:** Swift 6 with strict concurrency
- **UI Framework:** SwiftUI
- **Networking:** Apple Network framework (NWListener, NWConnection)
- **AI Engine:** Apple Foundation Models (LanguageModelSession)
- **Protocol:** HTTP/1.1 with Server-Sent Events (SSE)

## 🔒 Privacy

OrchardGrid is built with privacy as a core principle:

- **On-Device Processing** — All AI inference happens locally using Apple's Neural Engine
- **No Data Storage** — Cloud relay mode uses end-to-end encryption, no data is stored on servers
- **No Data Collection** — We don't collect any personal data or AI queries
- **Open Source** — Full transparency, audit the code yourself

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Links

- **Website:** [orchardgrid.com](https://orchardgrid.com)
- **App Store:** [Download](https://apps.apple.com/us/app/orchardgrid/id6754092757)
- **Dashboard:** [orchardgrid.com/dashboard](https://orchardgrid.com/dashboard)

---

<p align="center">
  Made with ❤️ for the Apple ecosystem
</p>

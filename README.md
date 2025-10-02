# Giant Big

**OpenAI-Compatible API Server for Apple Intelligence**

A modern macOS application that wraps Apple's Foundation Models (Apple Intelligence) as an OpenAI-compatible HTTP API server, enabling seamless integration with existing OpenAI client libraries and tools.

## Features

- ✅ **OpenAI API Compatible** - Drop-in replacement for OpenAI API
- ✅ **Structured Output** - Full JSON Schema support with runtime validation
- ✅ **Streaming Support** - Server-Sent Events (SSE) for real-time responses
- ✅ **Multi-turn Conversations** - Stateful session management with Transcript
- ✅ **Type-Safe** - Built with Swift 6 concurrency and Sendable protocols
- ✅ **Modern SwiftUI** - Clean, native macOS interface
- ✅ **Comprehensive Tests** - 100% coverage of structured output scenarios

## Requirements

- macOS 15.4+ (Sequoia)
- Xcode 16.0+
- Apple Intelligence enabled
- Python 3.8+ (for testing)

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/YOUR_USERNAME/giant_big.git
cd giant_big
```

### 2. Open in Xcode

```bash
open giant_big.xcodeproj
```

### 3. Build and Run

Press `Cmd+R` or click the Run button in Xcode.

The server will start on `http://localhost:8888`.

## API Usage

### Basic Chat Completion

```bash
curl -X POST http://localhost:8888/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "apple-intelligence",
    "messages": [
      {"role": "user", "content": "Hello!"}
    ]
  }'
```

### Streaming Response

```bash
curl -N -X POST http://localhost:8888/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "apple-intelligence",
    "messages": [
      {"role": "user", "content": "Count from 1 to 5"}
    ],
    "stream": true
  }'
```

### Structured Output

```bash
curl -X POST http://localhost:8888/v1/chat/completions \
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

### Multi-turn Conversation

```bash
curl -X POST http://localhost:8888/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "apple-intelligence",
    "messages": [
      {"role": "user", "content": "My name is Bob"},
      {"role": "assistant", "content": "Nice to meet you, Bob!"},
      {"role": "user", "content": "What is my name?"}
    ]
  }'
```

## Testing

### Install Python Dependencies

```bash
cd tests
pip3 install -r requirements.txt
```

### Run Tests

```bash
python3 test_structured_output.py
```

### Test Coverage

The test suite covers all JSON Schema features:

- ✅ Basic types (string, integer, number, boolean)
- ✅ Array types (string[], number[], boolean[], object[])
- ✅ Nested objects (single-level, multi-level)
- ✅ Enum types (anyOf constraints)
- ✅ Constraints (minimum, maximum, minItems, maxItems)
- ✅ Optional fields (isOptional: true)
- ✅ Complex nested structures (arrays of objects)
- ✅ Edge cases (boundary values, empty optionals)

## Architecture

### Project Structure

```
giant_big/
├── giant_big/
│   ├── APIServer.swift          # Core HTTP server and API logic
│   ├── SchemaConverter.swift    # JSON Schema to DynamicGenerationSchema converter
│   ├── ServerStatusView.swift   # SwiftUI status interface
│   └── giant_bigApp.swift       # Application entry point
├── tests/
│   ├── schemas/                 # JSON Schema test files
│   │   ├── test_cases.json      # Test configuration
│   │   ├── basic_types.json
│   │   ├── array_types.json
│   │   ├── nested_objects.json
│   │   ├── enum_types.json
│   │   ├── constraints.json
│   │   ├── optional_fields.json
│   │   ├── complex_nested.json
│   │   └── edge_cases.json
│   ├── test_structured_output.py
│   ├── validators.py
│   └── requirements.txt
└── README.md
```

### Key Components

#### APIServer.swift (734 lines)
- HTTP request parsing and routing
- OpenAI API compatibility layer
- Streaming response handling (SSE)
- Multi-turn conversation management
- Error handling and validation

#### SchemaConverter.swift (258 lines)
- Converts OpenAI JSON Schema to Apple's `DynamicGenerationSchema`
- Supports all JSON Schema types and constraints
- Recursive handling of nested structures
- Dependency management for schema references

#### ServerStatusView.swift (183 lines)
- Real-time server status display
- Request statistics and monitoring
- Modern SwiftUI interface with `.ultraThinMaterial`

## Supported JSON Schema Features

### Types
- `string` - Text values
- `integer` - Whole numbers
- `number` - Decimal numbers (Double)
- `boolean` - true/false values
- `array` - Lists of values
- `object` - Nested structures
- `enum` - Enumerated string values (anyOf)

### Constraints
- `minimum` / `maximum` - Numeric bounds
- `minItems` / `maxItems` - Array length bounds
- `required` - Required fields
- `additionalProperties` - Strict mode (false)

### Advanced Features
- Nested objects (multi-level)
- Arrays of objects
- Optional fields
- Enum constraints (anyOf)
- Schema references

## API Endpoints

### POST /v1/chat/completions

OpenAI-compatible chat completion endpoint.

**Request Body:**
```json
{
  "model": "apple-intelligence",
  "messages": [
    {"role": "user", "content": "Hello"}
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
  "object": "chat.completion",
  "model": "apple-intelligence",
  "choices": [{
    "finish_reason": "stop",
    "message": {
      "content": "Hello! How can I help you?",
      "role": "assistant"
    },
    "index": 0
  }],
  "created": 1234567890,
  "id": "chatcmpl-xxxxx",
  "usage": {
    "prompt_tokens": 0,
    "completion_tokens": 0,
    "total_tokens": 0
  }
}
```

### GET /v1/models

List available models.

**Response:**
```json
{
  "object": "list",
  "data": [{
    "id": "apple-intelligence",
    "object": "model",
    "created": 1234567890,
    "owned_by": "apple"
  }]
}
```

## Technical Details

### Concurrency
- Built with Swift 6 strict concurrency
- Uses `async/await` for all asynchronous operations
- `@MainActor` isolation for UI updates
- `nonisolated` for network operations
- `Sendable` protocol for thread-safe data

### Networking
- Apple's Network framework (`NWListener`, `NWConnection`)
- HTTP/1.1 protocol
- Server-Sent Events (SSE) for streaming
- Port 8888 (configurable)

### Apple Intelligence Integration
- `LanguageModelSession` for stateful conversations
- `Transcript` for multi-turn dialogue
- `DynamicGenerationSchema` for runtime structured output
- `GenerationSchema` for validated schemas
- `GeneratedContent` for structured responses

## License

MIT License - See LICENSE file for details

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Acknowledgments

- Built with Apple's Foundation Models framework
- Inspired by OpenAI's API design
- Uses Swift 6 modern concurrency features


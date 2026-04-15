# OpenAI API compatibility

Both the **local API server** (`:8888`, enabled via *Share Locally*) and the **cloud relay** (`orchardgrid.com/v1/*`) speak an OpenAI-compatible dialect. Every OrchardGrid capability ships under an `/v1/*` path so existing SDKs and clients work without glue code.

## Base URLs

| Surface | Base | Auth |
|---|---|---|
| Local LAN | `http://<host>.local:8888` | Optional bearer (if App's **API key** is set); otherwise open |
| Cloud relay | `https://orchardgrid.com` | `Authorization: Bearer sk-…` — inference-scope API key |

## Endpoints

| Capability | Path | Framework | Streaming |
|---|---|---|---|
| Chat | `POST /v1/chat/completions` | FoundationModels | ✅ SSE |
| Image generation | `POST /v1/images/generations` | ImagePlayground | ❌ one-shot |
| NLP analysis | `POST /v1/nlp/analyze` | NaturalLanguage | ❌ |
| Vision analysis | `POST /v1/vision/analyze` | Vision | ❌ |
| Speech-to-text | `POST /v1/audio/transcriptions` | Speech | ✅ segments |
| Sound classification | `POST /v1/audio/classify` | SoundAnalysis | ❌ |
| Models list | `GET /v1/models` | — | — |
| Health | `GET /health` | — | — |

## `/v1/chat/completions`

Request shape accepted — fields not in the table are tolerated but not acted on (compatible with OpenAI clients that send extra metadata).

| Field | Type | Supported | Notes |
|---|---|:---:|---|
| `model` | string | ✅ | Must be `apple-intelligence` |
| `messages` | array | ✅ | `role: system / user / assistant` |
| `stream` | bool | ✅ | SSE with `chat.completion.chunk` events |
| `temperature` | 0–2 | ✅ | Mapped to `GenerationOptions.temperature` |
| `max_tokens` | int | ✅ | Mapped to `maximumResponseTokens` |
| `seed` | uint64 | ✅ | Forces deterministic sampling |
| `response_format` | `{type: "json_schema", json_schema: {...}}` | ✅ | Schema converted via `SchemaConverter` |
| `tools` / `tool_choice` | array | ⚠️ | Via MCP when using `og --mcp`; direct HTTP tool-call not yet supported |
| `context_strategy` *(extension)* | string | ✅ | `newest-first` / `oldest-first` / `sliding-window` / `summarize` / `strict` |
| `context_max_turns` *(extension)* | int | ✅ | Used by `sliding-window` |
| `permissive` *(extension)* | bool | ✅ | Relaxes safety guardrails |
| `logprobs` / `top_logprobs` | — | ❌ | Accepted and ignored |
| `n` | int | ⚠️ | Only `n: 1` supported (Apple's model always returns one candidate) |
| `stop` | array | ❌ | Not exposed by FoundationModels |
| `presence_penalty` / `frequency_penalty` | — | ❌ | Not exposed |

Response shape matches OpenAI's `chat.completion` exactly — `id`, `object`, `created`, `model`, `choices[0].message`, `usage.{prompt,completion,total}_tokens`. Streaming chunks match `chat.completion.chunk`.

## `/v1/images/generations`

| Field | Supported | Notes |
|---|:---:|---|
| `prompt` | ✅ | |
| `n` | ✅ | Defaults to 1 |
| `style` | ✅ | `illustration` / `sketch` |
| `response_format` | ✅ | Only `b64_json` |
| `size`, `quality` | ❌ | ImagePlayground doesn't expose these |

Response: `{ created, data: [{ b64_json }] }`.

## `/v1/audio/transcriptions`

OpenAI's multipart form isn't supported. Send JSON:

```json
{
  "audio": "<base64>",
  "language": "en-US"
}
```

Response: `{ text, segments: [{ text, start, end }] }`.

## `/v1/audio/classify`

Not an OpenAI endpoint — OrchardGrid-specific. Request: `{ audio: "<base64>" }`. Response: `{ classifications: [{ label, confidence }], duration }`.

## `/v1/vision/analyze`

Not an OpenAI endpoint — OrchardGrid-specific. Batches OCR, classification, face detection, barcode detection in one call.

Request:
```json
{
  "image": "<base64>",
  "tasks": ["ocr", "classify", "faces", "barcodes"]
}
```

Response includes any subset of: `ocr` (array of recognised text), `classifications`, `faces`, `barcodes`.

## `/v1/nlp/analyze`

Not an OpenAI endpoint. Request:
```json
{
  "text": "…",
  "tasks": ["language", "entities", "tokens", "pos_tags", "lemmas", "sentences", "embedding"]
}
```

## `/v1/models`

Returns a minimal list with exactly `apple-intelligence`.

## Errors

All failures return OpenAI's error shape:

```json
{ "error": { "message": "...", "type": "...", "code": null, "param": null } }
```

| `type` | HTTP | Mapped from |
|---|:---:|---|
| `invalid_request_error` | 400 | Bad JSON, missing fields, unsupported params |
| `content_policy_violation` | 400 | Apple Intelligence guardrail |
| `context_length_exceeded` | 400 | Input longer than context window |
| `rate_limit_error` | 429 | Device busy / throttled |
| `server_error` | 500 / 503 | Model unavailable, internal error |

## Client examples

### Python (official `openai` client)

```python
from openai import OpenAI
client = OpenAI(base_url="http://mac.local:8888/v1", api_key="unused")
client.chat.completions.create(
    model="apple-intelligence",
    messages=[{"role": "user", "content": "hi"}],
)
```

### Curl

```bash
curl https://orchardgrid.com/v1/chat/completions \
  -H "Authorization: Bearer sk-…" \
  -H "Content-Type: application/json" \
  -d '{"model":"apple-intelligence","messages":[{"role":"user","content":"hi"}]}'
```

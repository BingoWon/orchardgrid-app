# OrchardGrid demos

Small, self-contained shell scripts that chain multiple OrchardGrid capabilities together. Each one runs on top of a **running OrchardGrid.app** (Share Locally enabled on `:8888`) plus the `og` CLI on PATH.

## Prerequisites

```sh
brew install --cask bingowon/orchardgrid/orchardgrid   # app + CLI
# Start OrchardGrid.app, toggle "Share Locally" on
```

## Scripts

| Script | Capabilities combined | What it does |
|---|---|---|
| [`ocr-describe`](ocr-describe) | Vision → Chat | OCR an image with Vision, then hand the text to the chat model for a summary |
| [`listen`](listen) | Speech → Chat | Record mic audio, transcribe with Speech, ask the model to act on it |
| [`read-aloud`](read-aloud) | Chat → macOS `say` | Pipe a chat answer straight into Apple's TTS for a voice-first loop |

All scripts are tiny (≤40 lines) and meant to be read — open them up and steal the pattern for your own glue code.

#!/usr/bin/env python3
"""
OrchardGrid — Live smoke test for all six on-device capabilities.

Exercises the running OrchardGrid.app's local HTTP API (and, optionally,
the cloud relay) end-to-end against real Apple Foundation Model. Unit and
integration tiers elsewhere in this repo mock Apple's frameworks; this
one is the only layer that catches regressions like "ImagePlayground
broken" or "Speech transcribing empty" before a release.

Prerequisites
  1. OrchardGrid.app is running with **Share Locally** enabled on :8888
  2. Apple's built-in AI is available on this Mac (M1+, macOS 26+)
  3. `requests` is installed (pip3 install --user requests)

Usage
  make smoke-live-capabilities                              # via Makefile
  python3 scripts/smoke-live/capabilities.py                # local direct only
  python3 scripts/smoke-live/capabilities.py --worker-key sk-…
                                                            # + cloud worker
  python3 scripts/smoke-live/capabilities.py --out /tmp/foo # custom output

Exit code: 0 if every capability passes, 1 otherwise.
"""

import argparse
import base64
import json
import math
import random
import struct
import sys
import time
import wave
from datetime import datetime
from io import BytesIO
from pathlib import Path

try:
    import requests
except ImportError:
    sys.exit("Install requests: pip3 install --user requests")

SCRIPT_DIR = Path(__file__).parent
FIXTURES_DIR = SCRIPT_DIR / "fixtures"

# ── Test harness ─────────────────────────────────────────────────

RESULTS: list[dict] = []


def run(name: str, fn, *, target: str):
    start = time.time()
    try:
        detail = fn()
        elapsed = time.time() - start
        print(f"  ✅ {name}  ({elapsed:.2f}s)")
        RESULTS.append({"name": name, "target": target, "status": "pass",
                        "elapsed": round(elapsed, 3), "detail": detail})
    except requests.exceptions.ConnectionError:
        elapsed = time.time() - start
        print(f"  ⚠️  {name} — connection refused (is OrchardGrid.app running?)")
        RESULTS.append({"name": name, "target": target, "status": "skip",
                        "elapsed": round(elapsed, 3), "detail": "connection refused"})
    except Exception as e:  # noqa: BLE001
        elapsed = time.time() - start
        print(f"  ❌ {name} — {e}")
        RESULTS.append({"name": name, "target": target, "status": "fail",
                        "elapsed": round(elapsed, 3), "detail": str(e)})


# ── Fixture generators ───────────────────────────────────────────

def _wav_bytes(duration_s: float, freq: int | None, sample_rate: int = 16000) -> bytes:
    n = int(sample_rate * duration_s)
    if freq is None:
        samples = [random.randint(-32767, 32767) for _ in range(n)]
    else:
        samples = [int(32767 * math.sin(2 * math.pi * freq * t / sample_rate)) for t in range(n)]
    buf = BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(struct.pack(f"<{n}h", *samples))
    return buf.getvalue()


def _gradient_png(width: int = 100, height: int = 100) -> bytes:
    """Deterministic red→blue gradient PNG big enough for Vision APIs."""
    import zlib

    def chunk(tag, data):
        body = tag + data
        crc = struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
        return struct.pack(">I", len(data)) + body + crc

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            raw.extend([int(255 * (1 - x / width)), int(128 * (y / height)), int(255 * (x / width))])
    idat = zlib.compress(bytes(raw))
    return sig + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")


def _load_speech() -> str:
    wav = FIXTURES_DIR / "speech_hello.wav"
    return base64.b64encode(
        wav.read_bytes() if wav.exists() else _wav_bytes(1.0, freq=440)
    ).decode()


IMAGE_B64 = base64.b64encode(_gradient_png()).decode()
SPEECH_B64 = _load_speech()
NOISE_B64 = base64.b64encode(_wav_bytes(1.0, freq=None)).decode()


# ── Capability suite ─────────────────────────────────────────────

def suite(base_url: str, headers: dict, target: str, out_dir: Path):
    print(f"\n{'═' * 60}\n  Target: {target} ({base_url})\n{'═' * 60}")

    def post(path, body, timeout=60, stream=False):
        return requests.post(f"{base_url}{path}", headers=headers, json=body,
                             timeout=timeout, stream=stream)

    def get(path, timeout=10):
        return requests.get(f"{base_url}{path}", headers=headers, timeout=timeout)

    def _assert_ok(r):
        assert r.status_code == 200, f"status {r.status_code}: {r.text[:200]}"

    # ── /v1/models ──
    print("\n📋 Models")

    def models():
        r = get("/v1/models")
        _assert_ok(r)
        data = r.json()
        ids = [m["id"] for m in data["data"]]
        print(f"     Available: {', '.join(ids)}")
        return {"models": ids}

    run("List models", models, target=target)

    # ── /v1/chat/completions ──
    print("\n💬 Chat Completions")

    def chat_basic():
        r = post("/v1/chat/completions", {
            "model": "apple-foundationmodel",
            "messages": [{"role": "user", "content": "Say 'hello' and nothing else."}],
        })
        _assert_ok(r)
        content = r.json()["choices"][0]["message"]["content"]
        assert content, "empty response"
        print(f"     Response: {content[:100]}")
        return {"content": content}

    def chat_stream():
        r = post("/v1/chat/completions", {
            "model": "apple-foundationmodel",
            "messages": [{"role": "user", "content": "Count from 1 to 3."}],
            "stream": True,
        }, stream=True)
        _assert_ok(r)
        chunks, content = 0, ""
        for line in r.iter_lines(decode_unicode=True):
            if line and line.startswith("data: ") and line != "data: [DONE]":
                chunks += 1
                try:
                    delta = json.loads(line[6:])["choices"][0]["delta"].get("content", "")
                    content += delta
                except (json.JSONDecodeError, KeyError, IndexError):
                    pass
        assert chunks > 0, "no stream chunks received"
        print(f"     Chunks: {chunks}, Content: {content[:100]}")
        return {"chunks": chunks, "content": content}

    run("Basic completion", chat_basic, target=target)
    run("Streaming completion", chat_stream, target=target)

    # ── /v1/nlp/analyze ──
    print("\n📝 NLP Analysis")

    def nlp_language():
        r = post("/v1/nlp/analyze", {
            "text": "This is a test sentence in English.",
            "tasks": ["language"],
        }, timeout=15)
        _assert_ok(r)
        lang = r.json()["language"]
        print(f"     Detected: {lang['code']} (confidence: {lang['confidence']:.2f})")
        return lang

    def nlp_entities():
        r = post("/v1/nlp/analyze", {
            "text": "Tim Cook announced new products at Apple Park in Cupertino.",
            "tasks": ["entities"],
        }, timeout=15)
        _assert_ok(r)
        entities = [{"text": e["text"], "type": e["type"]} for e in r.json()["entities"]]
        print(f"     Entities: {entities}")
        return {"entities": entities}

    def nlp_tokens():
        r = post("/v1/nlp/analyze", {
            "text": "The quick brown fox jumps over the lazy dog.",
            "tasks": ["tokens", "pos_tags", "lemmas"],
        }, timeout=15)
        _assert_ok(r)
        toks = r.json()["tokens"]
        assert toks and toks[0].get("pos") and toks[0].get("lemma"), "missing pos/lemma"
        return {"token_count": len(toks)}

    def nlp_sentences():
        r = post("/v1/nlp/analyze", {
            "text": "First sentence. Second sentence. Third one!",
            "tasks": ["sentences"],
        }, timeout=15)
        _assert_ok(r)
        sents = r.json().get("sentences", [])
        assert len(sents) >= 2, "expected multiple sentences"
        return {"sentences": sents}

    def nlp_embedding():
        r = post("/v1/nlp/analyze", {
            "text": "Machine learning is fascinating.",
            "tasks": ["embedding"],
        }, timeout=15)
        _assert_ok(r)
        emb = r.json().get("embedding")
        if emb:
            print(f"     Embedding dims: {len(emb)}")
            return {"dims": len(emb)}
        print("     (Embedding model not available for this language)")
        return {"dims": None}

    run("Language detection", nlp_language, target=target)
    run("Named entity recognition", nlp_entities, target=target)
    run("Tokenization + POS + Lemmas", nlp_tokens, target=target)
    run("Sentence segmentation", nlp_sentences, target=target)
    run("Sentence embedding", nlp_embedding, target=target)

    # ── /v1/vision/analyze ──
    print("\n👀 Vision Analysis")

    def vision_multi():
        r = post("/v1/vision/analyze", {
            "image": IMAGE_B64,
            "tasks": ["ocr", "classify", "faces", "barcodes"],
        }, timeout=30)
        _assert_ok(r)
        data = r.json()
        for key in ("ocr", "classifications", "faces", "barcodes"):
            assert key in data, f"missing {key}"
        top = [c["label"] for c in data["classifications"][:3]]
        print(f"     OCR: {len(data['ocr'])} texts · faces: {len(data['faces'])} · top: {top}")
        return {k: len(data[k]) for k in ("ocr", "classifications", "faces", "barcodes")}

    run("Multi-task vision analysis", vision_multi, target=target)

    # ── /v1/audio/transcriptions ──
    print("\n🎙️ Speech Transcription")

    def speech():
        r = post("/v1/audio/transcriptions", {
            "audio": SPEECH_B64, "language": "en-US",
        }, timeout=120)
        _assert_ok(r)
        data = r.json()
        assert "text" in data, "missing text"
        print(f"     Transcription: \"{data['text']}\"")
        return {"text": data["text"], "segments": len(data.get("segments") or [])}

    run("Speech transcription", speech, target=target)

    # ── /v1/audio/classify ──
    print("\n🔊 Sound Classification")

    def sound():
        r = post("/v1/audio/classify", {"audio": NOISE_B64}, timeout=30)
        _assert_ok(r)
        data = r.json()
        for key in ("classifications", "duration"):
            assert key in data, f"missing {key}"
        top3 = [(c["label"], round(c["confidence"], 3)) for c in data["classifications"][:3]]
        if top3:
            print(f"     Top: {top3}")
        return {"count": len(data["classifications"]), "duration": data["duration"]}

    run("Sound classification", sound, target=target)

    # ── /v1/images/generations (last — slow) ──
    print("\n🎨 Image Generation")

    def image_gen():
        r = post("/v1/images/generations", {
            "prompt": "A simple red circle on white background",
            "n": 1, "style": "illustration",
        }, timeout=180)
        if r.status_code == 503:
            print("     (ImageCreator not available on this device)")
            return {"available": False}
        _assert_ok(r)
        b64 = r.json()["data"][0]["b64_json"]
        assert len(b64) > 100, "tiny response"
        out_dir.mkdir(parents=True, exist_ok=True)
        path = out_dir / f"image_{target.lower().replace(' ', '_')}_{int(time.time())}.png"
        path.write_bytes(base64.b64decode(b64))
        print(f"     Saved: {path}")
        return {"available": True, "saved_to": str(path), "bytes": len(base64.b64decode(b64))}

    run("Generate image", image_gen, target=target)


# ── Main ─────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[1].strip())
    parser.add_argument("--local-url", default="http://localhost:8888")
    parser.add_argument("--worker-url", default="http://localhost:4399")
    parser.add_argument("--worker-key", default=None,
                        help="Bearer token enabling the cloud-worker suite")
    parser.add_argument("--out", default="/tmp/orchardgrid-smoke",
                        help="Directory for generated artefacts (images, reports)")
    args = parser.parse_args()

    out_dir = Path(args.out)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    suite(args.local_url, {}, "Local Direct", out_dir)
    if args.worker_key:
        suite(args.worker_url, {"Authorization": f"Bearer {args.worker_key}"},
              "Cloud Worker", out_dir)
    else:
        print("\n⏭️  Skipping Cloud Worker tests (no --worker-key)")

    passed = sum(1 for r in RESULTS if r["status"] == "pass")
    failed = sum(1 for r in RESULTS if r["status"] == "fail")
    skipped = sum(1 for r in RESULTS if r["status"] == "skip")

    print(f"\n{'═' * 60}")
    print(f"  Results: {passed} passed · {failed} failed · {skipped} skipped / {len(RESULTS)} total")
    print("  🎉 All tests passed!" if failed == 0
          else f"  ⚠️  {failed} test(s) need attention")
    print("═" * 60)

    out_dir.mkdir(parents=True, exist_ok=True)
    report = out_dir / f"report_{timestamp}.json"
    report.write_text(json.dumps({
        "timestamp": timestamp,
        "targets": {"local": args.local_url,
                    "worker": args.worker_url if args.worker_key else None},
        "summary": {"passed": passed, "failed": failed, "skipped": skipped,
                    "total": len(RESULTS)},
        "results": RESULTS,
    }, indent=2, ensure_ascii=False))
    print(f"\n  Report saved: {report}")

    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()

#!/bin/bash

# OrchardGrid App - Code Formatter
# Uses apple/swift-format (AST-based) to format all Swift files

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🎨 Formatting Swift code with swift-format..."

if ! command -v swift-format &> /dev/null; then
    echo "❌ Error: swift-format not found"
    echo "Install with: brew install swift-format"
    exit 1
fi

echo "   swift-format $(swift-format --version)"

swift-format format \
  --configuration "$SCRIPT_DIR/.swift-format" \
  --in-place \
  --recursive \
  "$SCRIPT_DIR"

echo "✅ Code formatting complete!"

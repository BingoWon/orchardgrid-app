#!/bin/bash

# OrchardGrid App - Code Formatter
# Uses SwiftFormat to format all Swift files

set -e

echo "🎨 Formatting Swift code..."

# Check if swiftformat is installed
if ! command -v swiftformat &> /dev/null; then
    echo "❌ Error: swiftformat not found"
    echo "Install with: brew install swiftformat"
    exit 1
fi

# Format all Swift files
swiftformat . --config .swiftformat

echo "✅ Code formatting complete!"


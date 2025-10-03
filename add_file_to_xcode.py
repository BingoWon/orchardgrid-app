#!/usr/bin/env python3
"""
Add SharedTypes.swift to Xcode project
"""
import subprocess
import sys

# Use xcodebuild to add the file
project_path = "orchardgrid-app.xcodeproj"
file_path = "orchardgrid-app/SharedTypes.swift"

# First, let's just rebuild the project to trigger SourceKit indexing
print("Cleaning build folder...")
subprocess.run([
    "xcodebuild",
    "-project", project_path,
    "-scheme", "orchardgrid-app",
    "clean"
], check=True)

print("Building project...")
subprocess.run([
    "xcodebuild",
    "-project", project_path,
    "-scheme", "orchardgrid-app",
    "build"
], check=True)

print("Done!")


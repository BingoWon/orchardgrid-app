#!/usr/bin/env python3
"""
Add SharedTypes.swift to Xcode project
"""
from pbxproj import XcodeProject

# Open the project
project = XcodeProject.load('orchardgrid-app.xcodeproj/project.pbxproj')

# Add the file to the project (without parent, it will add to the root)
project.add_file('orchardgrid-app/SharedTypes.swift')

# Save the project
project.save()

print("Successfully added SharedTypes.swift to the project!")


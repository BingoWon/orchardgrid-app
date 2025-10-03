#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'orchardgrid-app.xcodeproj'
file_path = 'orchardgrid-app/SharedTypes.swift'

# Open the project
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.first

# Get the main group
main_group = project.main_group['orchardgrid-app']

# Add the file to the project
file_ref = main_group.new_file(file_path)

# Add the file to the target's sources build phase
target.source_build_phase.add_file_reference(file_ref)

# Save the project
project.save

puts "Successfully added #{file_path} to #{project_path}"


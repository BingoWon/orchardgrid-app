#!/bin/bash

#
# clean-keychain.sh
# Clean all OrchardGrid Keychain entries
#

set -e

echo "🧹 Cleaning OrchardGrid Keychain entries..."

# Clean old entries
echo "Removing old Keychain entries..."
security delete-generic-password -s "com.orchardgrid.app" -a "auth_token" 2>/dev/null || true
security delete-generic-password -s "com.orchardgrid.app" -a "auth_token_development" 2>/dev/null || true
security delete-generic-password -s "com.orchardgrid.app" -a "auth_token_production" 2>/dev/null || true

# Clean new entries
security delete-generic-password -s "com.orchardgrid.app.dev" -a "auth_token_development" 2>/dev/null || true
security delete-generic-password -s "com.orchardgrid.app" -a "auth_token_production" 2>/dev/null || true

echo "✅ Keychain cleanup complete!"
echo ""
echo "Next steps:"
echo "1. Restart the app"
echo "2. Login again"
echo "3. No Keychain authorization prompt should appear"


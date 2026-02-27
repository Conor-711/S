#!/bin/bash

# S App - Development Data Cleanup Script
# This script removes all cached data and preferences for a fresh installation

set -e

BUNDLE_ID="com.mindcraft.notifier.S"
APP_SUPPORT_DIR="$HOME/Library/Application Support/S"
CACHE_DIR="$HOME/Library/Caches/$BUNDLE_ID"
PREFERENCES_FILE="$HOME/Library/Preferences/$BUNDLE_ID.plist"

echo "🧹 Cleaning up S app development data..."
echo ""

# 1. Clear UserDefaults (preferences)
echo "1️⃣ Clearing UserDefaults preferences..."
if defaults read "$BUNDLE_ID" &>/dev/null; then
    defaults delete "$BUNDLE_ID"
    echo "   ✅ Removed preferences: $BUNDLE_ID"
else
    echo "   ℹ️  No preferences found for $BUNDLE_ID"
fi

# Also remove the plist file directly
if [ -f "$PREFERENCES_FILE" ]; then
    rm -f "$PREFERENCES_FILE"
    echo "   ✅ Removed plist file: $PREFERENCES_FILE"
fi

# 2. Remove Application Support directory (captures, history.json)
echo ""
echo "2️⃣ Removing Application Support data..."
if [ -d "$APP_SUPPORT_DIR" ]; then
    rm -rf "$APP_SUPPORT_DIR"
    echo "   ✅ Removed: $APP_SUPPORT_DIR"
else
    echo "   ℹ️  No Application Support directory found"
fi

# 3. Remove cache directory
echo ""
echo "3️⃣ Removing cache directory..."
if [ -d "$CACHE_DIR" ]; then
    rm -rf "$CACHE_DIR"
    echo "   ✅ Removed: $CACHE_DIR"
else
    echo "   ℹ️  No cache directory found"
fi

# 4. Clear Sparkle update preferences
echo ""
echo "4️⃣ Clearing Sparkle update data..."
defaults delete "$BUNDLE_ID" SULastCheckTime 2>/dev/null && echo "   ✅ Cleared last update check time" || echo "   ℹ️  No Sparkle data found"
defaults delete "$BUNDLE_ID" SUEnableAutomaticChecks 2>/dev/null || true
defaults delete "$BUNDLE_ID" SUHasLaunchedBefore 2>/dev/null || true

echo ""
echo "✅ Cleanup complete! The app will start fresh on next launch."
echo ""
echo "📝 Cleaned items:"
echo "   - All OAuth tokens (Notion, Slack, Supabase)"
echo "   - Notion schema configuration"
echo "   - Capture history and screenshots"
echo "   - All UserDefaults preferences"
echo "   - Sparkle update preferences"
echo ""

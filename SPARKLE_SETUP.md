# Sparkle Auto-Update Setup Guide

This document explains how to complete the Sparkle auto-update integration for the S app.

## Prerequisites

- Xcode 14 or later
- macOS 12 or later for development
- A web server to host the appcast.xml file

## Step 1: Add Sparkle Package via Swift Package Manager

1. Open `S.xcodeproj` in Xcode
2. Go to **File → Add Package Dependencies...**
3. Enter the Sparkle repository URL:
   ```
   https://github.com/sparkle-project/Sparkle
   ```
4. Select version **2.x** (latest stable)
5. Click **Add Package**
6. Ensure the Sparkle library is added to the **S** target

## Step 2: Generate EdDSA Signing Keys

Sparkle uses EdDSA (ed25519) signatures to verify update integrity.

### Find the generate_keys tool

After adding Sparkle via SPM, the tools are located at:
```
~/Library/Developer/Xcode/DerivedData/S-xxx/SourcePackages/artifacts/sparkle/Sparkle/bin/
```

Or download from: https://github.com/sparkle-project/Sparkle/releases/latest

### Generate keys

```bash
# Navigate to Sparkle bin directory
cd /path/to/Sparkle/bin

# Generate a new key pair (only do this once!)
./generate_keys
```

This will:
1. Save the **private key** in your macOS Keychain (keep this safe!)
2. Print the **public key** to the console

### Update Info.plist

Copy the public key and update `S/Info.plist`:

```xml
<key>SUPublicEDKey</key>
<string>YOUR_ACTUAL_PUBLIC_KEY_HERE</string>
```

## Step 3: Configure the Appcast URL

Update `S/Info.plist` with your actual appcast URL:

```xml
<key>SUFeedURL</key>
<string>https://your-domain.com/appcast.xml</string>
```

## Step 4: Create and Host the Appcast

### Appcast XML Structure

Create an `appcast.xml` file on your server:

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>S App Updates</title>
        <link>https://your-domain.com/appcast.xml</link>
        <description>Most recent updates to S</description>
        <language>en</language>
        <item>
            <title>Version 1.4</title>
            <sparkle:version>1.4</sparkle:version>
            <sparkle:shortVersionString>1.4</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <pubDate>Wed, 22 Jan 2026 00:00:00 +0000</pubDate>
            <enclosure 
                url="https://your-domain.com/releases/S-1.4.zip"
                sparkle:edSignature="YOUR_SIGNATURE_HERE"
                length="12345678"
                type="application/octet-stream"/>
            <sparkle:releaseNotesLink>https://your-domain.com/release-notes/1.4.html</sparkle:releaseNotesLink>
        </item>
    </channel>
</rss>
```

### Sign your update archive

```bash
# Sign the update archive
./sign_update /path/to/S-1.4.zip

# This outputs the EdDSA signature to add to the appcast
```

## Step 5: Build and Archive for Distribution

1. **Archive the app:**
   - Product → Archive
   
2. **Export the app:**
   - Distribute App → Developer ID → Export

3. **Create update package:**
   ```bash
   # Create a ZIP of the app
   cd /path/to/exported/app
   zip -r S-1.4.zip S.app
   
   # Sign the archive
   /path/to/Sparkle/bin/sign_update S-1.4.zip
   ```

4. **Update appcast.xml** with:
   - New version number
   - File size (in bytes)
   - EdDSA signature from sign_update
   - Download URL

5. **Upload files to server:**
   - Upload `S-1.4.zip` to your releases directory
   - Update `appcast.xml`

## Configuration Options

### Info.plist Keys

| Key | Description | Default |
|-----|-------------|---------|
| `SUFeedURL` | URL to the appcast.xml | Required |
| `SUPublicEDKey` | Public EdDSA key for signature verification | Required |
| `SUEnableAutomaticChecks` | Enable automatic update checks | `true` |
| `SUAllowsAutomaticUpdates` | Allow automatic download/install | `true` |
| `SUAutomaticallyUpdate` | Install updates without user interaction | `false` |
| `SUScheduledCheckInterval` | Seconds between automatic checks | `86400` (1 day) |

## Testing

1. Build and run the app
2. Click the menu bar icon → "Check for Updates…"
3. Sparkle will check the appcast URL and show available updates

### Test with a local server

```bash
# Start a simple HTTP server in your appcast directory
cd /path/to/appcast
python3 -m http.server 8080

# Update SUFeedURL temporarily
# <string>http://localhost:8080/appcast.xml</string>
```

## Security Best Practices

1. **Keep private keys secure** - Never commit them to version control
2. **Use HTTPS** - Always serve appcast and updates over HTTPS
3. **Code sign your app** - Use Developer ID for distribution
4. **Notarize your app** - Required for macOS 10.15+

## Troubleshooting

### "Unable to check for updates"
- Verify `SUFeedURL` is accessible
- Check network connectivity
- Ensure appcast.xml is valid XML

### "Update is not signed correctly"
- Verify `SUPublicEDKey` matches the private key used to sign
- Re-sign the update with `sign_update`
- Check the signature in appcast.xml

### Console logs
Look for Sparkle logs in Console.app:
```
process:S subsystem:org.sparkle-project.Sparkle
```

## Resources

- [Sparkle Documentation](https://sparkle-project.org/documentation/)
- [Sparkle GitHub](https://github.com/sparkle-project/Sparkle)
- [App Transport Security](https://sparkle-project.org/documentation/app-transport-security/)

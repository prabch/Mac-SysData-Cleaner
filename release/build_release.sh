#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Change to the script's directory so paths are relative to it
cd "$(dirname "$0")"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting Mac SysData Cleaner Release Process...${NC}"

# 1. Load Environment Variables
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found.${NC}"
    echo -e "Please copy .env.template to .env and fill in your credentials:"
    echo -e "cp .env.template .env"
    exit 1
fi

source .env

# Validate required variables
REQUIRED_VARS=("TEAM_ID" "DEVELOPER_ID_CERT_HASH" "NOTARYTOOL_KEYCHAIN_PROFILE")
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo -e "${RED}Error: $var is not set in the .env file.${NC}"
        exit 1
    fi
done

# Configuration variables
APP_NAME="Mac SysData Cleaner"
APP_NAME_DASH="Mac-SysData-Cleaner"
# Project path is one level up since this script is in the "release" folder
PROJECT_PATH="../mac sysdata cleaner.xcodeproj"
SCHEME_NAME="mac sysdata cleaner"

# Build directories
BUILD_DIR="./build"
TEMP_BUILD_DIR="${BUILD_DIR}/temp"
TEMP_ARCHIVE_PATH="${TEMP_BUILD_DIR}/${APP_NAME_DASH}.xcarchive"
TEMP_EXPORT_PATH="${TEMP_BUILD_DIR}/export"
TEMP_APP_BUNDLE="${TEMP_EXPORT_PATH}/${APP_NAME}.app"

# Clean previous temporary build artifacts (leave old versions untouched)
echo -e "${YELLOW}Cleaning temporary build directory...${NC}"
rm -rf "${TEMP_BUILD_DIR}"
mkdir -p "${TEMP_BUILD_DIR}"

# 2. Generate ExportOptions.plist dynamically using TEAM_ID
cat > "${TEMP_BUILD_DIR}/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
</dict>
</plist>
EOF

# 3. Archive the project using xcodebuild
echo -e "${YELLOW}Archiving project with xcodebuild...${NC}"

# Define the build command as an array to keep it clean
XCODEBUILD_CMD=(
    xcodebuild clean archive
    -project "${PROJECT_PATH}"
    -scheme "${SCHEME_NAME}"
    -configuration Release
    -destination "generic/platform=macOS"
    -archivePath "${TEMP_ARCHIVE_PATH}"
)

if command -v xcpretty &> /dev/null; then
    "${XCODEBUILD_CMD[@]}" | xcpretty
else
    "${XCODEBUILD_CMD[@]}"
fi

# 4. Export the Archive
echo -e "${YELLOW}Exporting Archive (Developer ID Distribution)...${NC}"
xcodebuild -exportArchive \
    -archivePath "${TEMP_ARCHIVE_PATH}" \
    -exportOptionsPlist "${TEMP_BUILD_DIR}/ExportOptions.plist" \
    -exportPath "${TEMP_EXPORT_PATH}"

# Verify the app bundle exists in temp
if [ ! -d "${TEMP_APP_BUNDLE}" ]; then
    echo -e "${RED}Error: Exported App bundle not found at ${TEMP_APP_BUNDLE}${NC}"
    exit 1
fi

# 5. Extract version and create versioned directory
echo -e "${YELLOW}Extracting app version...${NC}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${TEMP_APP_BUNDLE}/Contents/Info.plist")
echo -e "${GREEN}Detected Version: ${VERSION}${NC}"

VERSION_DIR="${BUILD_DIR}/${VERSION}"
rm -rf "${VERSION_DIR}"
mkdir -p "${VERSION_DIR}"

# Move artifacts to the versioned directory
mv "${TEMP_ARCHIVE_PATH}" "${VERSION_DIR}/"
mv "${TEMP_APP_BUNDLE}" "${VERSION_DIR}/"
rm -rf "${TEMP_BUILD_DIR}"

# Define versioned paths
ARCHIVE_PATH="${VERSION_DIR}/${APP_NAME_DASH}.xcarchive"
APP_BUNDLE="${VERSION_DIR}/${APP_NAME}.app"
DMG_NAME="${APP_NAME_DASH}.dmg"
DMG_PATH="${VERSION_DIR}/${DMG_NAME}"

# 6. Package into DMG
echo -e "${YELLOW}Packaging app into DMG...${NC}"
if command -v create-dmg &> /dev/null; then
    # We use create-dmg for a nice visual installer
    create-dmg \
        --volname "${APP_NAME_DASH}" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "${APP_NAME}.app" 175 190 \
        --hide-extension "${APP_NAME}.app" \
        --app-drop-link 425 190 \
        "${DMG_PATH}" \
        "${APP_BUNDLE}"
else
    echo -e "${YELLOW}create-dmg not found. Falling back to basic hdiutil packaging...${NC}"
    mkdir -p "${VERSION_DIR}/dmg_temp"
    cp -R "${APP_BUNDLE}" "${VERSION_DIR}/dmg_temp/"
    ln -s /Applications "${VERSION_DIR}/dmg_temp/Applications"
    hdiutil create -volname "${APP_NAME_DASH}" -srcfolder "${VERSION_DIR}/dmg_temp" -ov -format UDZO "${DMG_PATH}"
    rm -rf "${VERSION_DIR}/dmg_temp"
fi

# 7. Sign the DMG
echo -e "${YELLOW}Signing the DMG with Developer ID Application Certificate...${NC}"
codesign --force --sign "${DEVELOPER_ID_CERT_HASH}" "${DMG_PATH}"

# 8. Notarize the DMG
echo -e "${YELLOW}Submitting the DMG to Apple for Notarization (this may take a few minutes)...${NC}"
xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${NOTARYTOOL_KEYCHAIN_PROFILE}" --wait

# 9. Staple the Notarization Ticket
echo -e "${YELLOW}Stapling Notarization Ticket to the DMG...${NC}"
xcrun stapler staple "${DMG_PATH}"

# 10. Verify the DMG
echo -e "${YELLOW}Verifying signature and notarization...${NC}"
spctl --assess --verbose --type open --context context:primary-signature "${DMG_PATH}"

echo -e "${GREEN}==================================================================${NC}"
echo -e "${GREEN}Success! Your release DMG is fully signed, notarized, and ready.${NC}"
echo -e "${GREEN}Location: ${DMG_PATH}${NC}"
echo -e "${GREEN}==================================================================${NC}"

# 11. Cleanup prompt (interactive terminal only)
if [ -t 0 ]; then
    echo -e ""
    read -p "Do you want to clean up temporary build files (archive and app), leaving only the DMG? (y/N): " CLEAN_UP
    if [[ "$CLEAN_UP" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Cleaning up temporary build files...${NC}"
        rm -rf "${ARCHIVE_PATH}"
        rm -rf "${APP_BUNDLE}"
        echo -e "${GREEN}Cleanup complete! Only the DMG remains in ${VERSION_DIR}.${NC}"
    else
        echo -e "${YELLOW}Cleanup skipped. All build artifacts kept in ${VERSION_DIR}.${NC}"
    fi
else
    echo -e "${YELLOW}Non-interactive shell. Cleanup skipped. All build artifacts kept in ${VERSION_DIR}.${NC}"
fi


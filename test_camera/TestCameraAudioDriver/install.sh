#!/bin/bash
#
# install.sh - Install the TestCameraAudioDriver HAL plugin
#
# Usage: sudo ./install.sh [path-to-driver-bundle]
#
# If no path is provided, it looks in the standard Xcode build location.
#

set -e

DRIVER_NAME="TestCameraAudioDriver.driver"
INSTALL_DIR="/Library/Audio/Plug-Ins/HAL"

# Find the driver bundle
if [ -n "$1" ]; then
    DRIVER_PATH="$1"
else
    # Try common Xcode build locations
    DRIVER_PATH="$(find ~/Library/Developer/Xcode/DerivedData -name "$DRIVER_NAME" -type d 2>/dev/null | head -1)"
fi

if [ -z "$DRIVER_PATH" ] || [ ! -d "$DRIVER_PATH" ]; then
    echo "Error: Cannot find $DRIVER_NAME"
    echo "Usage: sudo $0 /path/to/$DRIVER_NAME"
    exit 1
fi

echo "Installing $DRIVER_NAME from: $DRIVER_PATH"

# Remove existing installation
if [ -d "$INSTALL_DIR/$DRIVER_NAME" ]; then
    echo "Removing existing installation..."
    sudo rm -rf "$INSTALL_DIR/$DRIVER_NAME"
fi

# Copy the driver
echo "Copying to $INSTALL_DIR/"
sudo cp -R "$DRIVER_PATH" "$INSTALL_DIR/"

# Set permissions
sudo chown -R root:wheel "$INSTALL_DIR/$DRIVER_NAME"
sudo chmod -R 755 "$INSTALL_DIR/$DRIVER_NAME"

# Restart coreaudiod to pick up the new driver
echo "Restarting coreaudiod..."
sudo launchctl kickstart -k system/com.apple.audio.coreaudiod

echo ""
echo "Done! 'Test Camera Audio' should now appear in:"
echo "  System Settings > Sound > Input"
echo ""
echo "To uninstall:"
echo "  sudo rm -rf \"$INSTALL_DIR/$DRIVER_NAME\""
echo "  sudo launchctl kickstart -k system/com.apple.audio.coreaudiod"

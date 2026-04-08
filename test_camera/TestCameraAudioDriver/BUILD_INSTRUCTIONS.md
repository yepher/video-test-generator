# TestCameraAudioDriver - Build Instructions

## Add Target in Xcode

1. Open TestCamera.xcodeproj
2. File > New > Target...
3. Select **macOS** > **Bundle** (under Framework & Library)
4. Name: `TestCameraAudioDriver`
5. Language: C++
6. Bundle Extension: `driver`
7. Click Finish

## Configure the Target

### Build Settings
1. Select the TestCameraAudioDriver target
2. Build Settings > search "wrapper extension" > set to `driver`
3. Build Settings > search "product name" > set to `TestCameraAudioDriver`
4. Build Settings > search "bundle identifier" > set to `com.yepher.vidtiming.testcamera.audiodriver`
5. Build Settings > search "info.plist" > point to `TestCameraAudioDriver/Info.plist`

### Add Source Files
1. Right-click TestCameraAudioDriver group in navigator
2. Add files: TestCameraAudioDriver.cpp, TestCameraAudioDriver.h, AudioPatterns.cpp, AudioPatterns.h
3. Make sure they're added to the TestCameraAudioDriver target only

### Link Frameworks
1. Select TestCameraAudioDriver target > Build Phases > Link Binary With Libraries
2. Add: CoreAudio.framework, CoreFoundation.framework

## Build and Install

```bash
# Build in Xcode (Cmd+B with TestCameraAudioDriver scheme selected)

# Then install:
sudo ./TestCameraAudioDriver/install.sh

# Or manually:
sudo cp -R ~/Library/Developer/Xcode/DerivedData/TestCamera-*/Build/Products/Debug/TestCameraAudioDriver.driver /Library/Audio/Plug-Ins/HAL/
sudo launchctl kickstart -k system/com.apple.audio.coreaudiod
```

## Verify

Open System Settings > Sound > Input - "Test Camera Audio" should appear.

## Uninstall

```bash
sudo rm -rf /Library/Audio/Plug-Ins/HAL/TestCameraAudioDriver.driver
sudo launchctl kickstart -k system/com.apple.audio.coreaudiod
```

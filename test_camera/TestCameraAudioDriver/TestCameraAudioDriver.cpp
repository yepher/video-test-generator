//
//  TestCameraAudioDriver.cpp
//  TestCameraAudioDriver
//
//  CoreAudio HAL AudioServerPlugIn implementation.
//  Creates a virtual microphone "Test Camera Audio" that generates
//  audio matching the selected video test pattern.
//
//  Object hierarchy:
//    Plugin (kAudioObjectPlugInObject)
//      └─ Device (kObjectID_Device) "Test Camera Audio"
//           └─ Stream (kObjectID_Stream) - 1ch Float32 48kHz input
//

#include "TestCameraAudioDriver.h"
#include "AudioPatterns.h"

// ============================================================================
#pragma mark - Forward Declarations
// ============================================================================

static HRESULT         _QueryInterface(void *inDriver, REFIID inUUID, LPVOID *outInterface);
static ULONG           _AddRef(void *inDriver);
static ULONG           _Release(void *inDriver);
static OSStatus        _Initialize(AudioServerPlugInDriverRef inDriver, AudioServerPlugInHostRef inHost);
static OSStatus        _CreateDevice(AudioServerPlugInDriverRef d, CFDictionaryRef desc, const AudioServerPlugInClientInfo *c, AudioObjectID *o);
static OSStatus        _DestroyDevice(AudioServerPlugInDriverRef d, AudioObjectID o);
static OSStatus        _AddDeviceClient(AudioServerPlugInDriverRef d, AudioObjectID o, const AudioServerPlugInClientInfo *c);
static OSStatus        _RemoveDeviceClient(AudioServerPlugInDriverRef d, AudioObjectID o, const AudioServerPlugInClientInfo *c);
static OSStatus        _PerformDeviceConfigurationChange(AudioServerPlugInDriverRef d, AudioObjectID o, UInt64 a, void *p);
static OSStatus        _AbortDeviceConfigurationChange(AudioServerPlugInDriverRef d, AudioObjectID o, UInt64 a, void *p);
static Boolean         _HasProperty(AudioServerPlugInDriverRef d, AudioObjectID o, pid_t c, const AudioObjectPropertyAddress *a);
static OSStatus        _IsPropertySettable(AudioServerPlugInDriverRef d, AudioObjectID o, pid_t c, const AudioObjectPropertyAddress *a, Boolean *out);
static OSStatus        _GetPropertyDataSize(AudioServerPlugInDriverRef d, AudioObjectID o, pid_t c, const AudioObjectPropertyAddress *a, UInt32 qSize, const void *qData, UInt32 *outSize);
static OSStatus        _GetPropertyData(AudioServerPlugInDriverRef d, AudioObjectID o, pid_t c, const AudioObjectPropertyAddress *a, UInt32 qSize, const void *qData, UInt32 inSize, UInt32 *outSize, void *outData);
static OSStatus        _SetPropertyData(AudioServerPlugInDriverRef d, AudioObjectID o, pid_t c, const AudioObjectPropertyAddress *a, UInt32 qSize, const void *qData, UInt32 inSize, const void *inData);
static OSStatus        _StartIO(AudioServerPlugInDriverRef d, AudioObjectID o, UInt32 clientID);
static OSStatus        _StopIO(AudioServerPlugInDriverRef d, AudioObjectID o, UInt32 clientID);
static OSStatus        _GetZeroTimeStamp(AudioServerPlugInDriverRef d, AudioObjectID o, UInt32 clientID, Float64 *outSampleTime, UInt64 *outHostTime, UInt64 *outSeed);
static OSStatus        _WillDoIOOperation(AudioServerPlugInDriverRef d, AudioObjectID o, UInt32 clientID, UInt32 opID, Boolean *outWillDo, Boolean *outWillDoInPlace);
static OSStatus        _BeginIOOperation(AudioServerPlugInDriverRef d, AudioObjectID o, UInt32 clientID, UInt32 opID, UInt32 ioSize, const AudioServerPlugInIOCycleInfo *ioCycleInfo);
static OSStatus        _DoIOOperation(AudioServerPlugInDriverRef d, AudioObjectID o, AudioObjectID s, UInt32 clientID, UInt32 opID, UInt32 ioSize, const AudioServerPlugInIOCycleInfo *ioCycleInfo, void *ioMainBuffer, void *ioSecondaryBuffer);
static OSStatus        _EndIOOperation(AudioServerPlugInDriverRef d, AudioObjectID o, UInt32 clientID, UInt32 opID, UInt32 ioSize, const AudioServerPlugInIOCycleInfo *ioCycleInfo);

// ============================================================================
#pragma mark - Vtable
// ============================================================================

static AudioServerPlugInDriverInterface gDriverInterface = {
    NULL,  // _reserved
    _QueryInterface,
    _AddRef,
    _Release,
    _Initialize,
    _CreateDevice,
    _DestroyDevice,
    _AddDeviceClient,
    _RemoveDeviceClient,
    _PerformDeviceConfigurationChange,
    _AbortDeviceConfigurationChange,
    _HasProperty,
    _IsPropertySettable,
    _GetPropertyDataSize,
    _GetPropertyData,
    _SetPropertyData,
    _StartIO,
    _StopIO,
    _GetZeroTimeStamp,
    _WillDoIOOperation,
    _BeginIOOperation,
    _DoIOOperation,
    _EndIOOperation
};

static AudioServerPlugInDriverInterface *gDriverInterfacePtr = &gDriverInterface;
static TestCameraAudioDriverState gDriverState;
static AudioGenContext gAudioCtx;

// State file path (must match kAudioStatePath in Config.swift)
static const char *kStateFilePath = "/tmp/com.testcamera.audio.state";

// ============================================================================
#pragma mark - Factory Function
// ============================================================================

extern "C" void* TestCameraAudioDriverFactory(CFAllocatorRef allocator, CFUUIDRef requestedTypeUUID)
{
    // Check that the requested type is AudioServerPlugIn
    CFUUIDRef audioServerPlugInTypeUUID = CFUUIDCreateFromString(NULL, CFSTR("443ABAB8-E7B3-491A-B985-BEB9187030DB"));
    if (!CFEqual(requestedTypeUUID, audioServerPlugInTypeUUID)) {
        CFRelease(audioServerPlugInTypeUUID);
        return NULL;
    }
    CFRelease(audioServerPlugInTypeUUID);

    // Initialize state
    memset(&gDriverState, 0, sizeof(gDriverState));
    gDriverState.refCount = 1;
    gDriverState.stateFD = -1;
    gDriverState.sharedState = NULL;
    pthread_mutex_init(&gDriverState.mutex, NULL);

    memset(&gAudioCtx, 0, sizeof(gAudioCtx));
    gAudioCtx.sampleRate = kDevice_SampleRate;

    return &gDriverInterfacePtr;
}

// ============================================================================
#pragma mark - IUnknown
// ============================================================================

static HRESULT _QueryInterface(void *inDriver, REFIID inUUID, LPVOID *outInterface)
{
    // AudioServerPlugIn type UUID
    CFUUIDRef audioServerPlugInTypeUUID = CFUUIDCreateFromString(NULL, CFSTR("443ABAB8-E7B3-491A-B985-BEB9187030DB"));
    // AudioServerPlugInDriverInterface UUID (kAudioServerPlugInDriverInterfaceUUID)
    CFUUIDRef audioServerPlugInInterfaceUUID = CFUUIDGetConstantUUIDWithBytes(NULL, 0xEE, 0xA5, 0x77, 0x3D, 0xCC, 0x43, 0x49, 0xF1, 0x8E, 0x00, 0x8F, 0x96, 0xE7, 0xD2, 0x3B, 0x17);
    // IUnknown UUID
    CFUUIDRef iUnknownUUID = CFUUIDGetConstantUUIDWithBytes(NULL,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46);
    CFUUIDRef requestedUUID = CFUUIDCreateFromUUIDBytes(NULL, inUUID);

    Boolean match = CFEqual(requestedUUID, iUnknownUUID) ||
                    CFEqual(requestedUUID, audioServerPlugInTypeUUID) ||
                    CFEqual(requestedUUID, audioServerPlugInInterfaceUUID);

    CFRelease(audioServerPlugInTypeUUID);
    // audioServerPlugInInterfaceUUID is a constant — don't release
    CFRelease(requestedUUID);

    if (match) {
        _AddRef(inDriver);
        *outInterface = inDriver;
        return S_OK;
    }

    *outInterface = NULL;
    return E_NOINTERFACE;
}

static ULONG _AddRef(void *inDriver)
{
    return __sync_add_and_fetch(&gDriverState.refCount, 1);
}

static ULONG _Release(void *inDriver)
{
    UInt32 count = __sync_sub_and_fetch(&gDriverState.refCount, 1);
    if (count == 0) {
        pthread_mutex_destroy(&gDriverState.mutex);
    }
    return count;
}

// ============================================================================
#pragma mark - Initialize
// ============================================================================

static OSStatus _Initialize(AudioServerPlugInDriverRef inDriver, AudioServerPlugInHostRef inHost)
{
    gDriverState.host = inHost;
    return kAudioHardwareNoError;
}

// ============================================================================
#pragma mark - Device lifecycle (not supported - static device)
// ============================================================================

static OSStatus _CreateDevice(AudioServerPlugInDriverRef d, CFDictionaryRef desc, const AudioServerPlugInClientInfo *c, AudioObjectID *o)
{
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus _DestroyDevice(AudioServerPlugInDriverRef d, AudioObjectID o)
{
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus _AddDeviceClient(AudioServerPlugInDriverRef d, AudioObjectID o, const AudioServerPlugInClientInfo *c)
{
    return kAudioHardwareNoError;
}

static OSStatus _RemoveDeviceClient(AudioServerPlugInDriverRef d, AudioObjectID o, const AudioServerPlugInClientInfo *c)
{
    return kAudioHardwareNoError;
}

static OSStatus _PerformDeviceConfigurationChange(AudioServerPlugInDriverRef d, AudioObjectID o, UInt64 a, void *p)
{
    return kAudioHardwareNoError;
}

static OSStatus _AbortDeviceConfigurationChange(AudioServerPlugInDriverRef d, AudioObjectID o, UInt64 a, void *p)
{
    return kAudioHardwareNoError;
}

// ============================================================================
#pragma mark - Property Support: HasProperty
// ============================================================================

static Boolean _HasProperty(AudioServerPlugInDriverRef d, AudioObjectID objectID, pid_t clientPID, const AudioObjectPropertyAddress *address)
{
    switch (objectID) {
        case kObjectID_PlugIn:
            switch (address->mSelector) {
                case kAudioObjectPropertyBaseClass:
                case kAudioObjectPropertyClass:
                case kAudioObjectPropertyOwner:
                case kAudioObjectPropertyManufacturer:
                case kAudioObjectPropertyOwnedObjects:
                case kAudioPlugInPropertyDeviceList:
                case kAudioPlugInPropertyTranslateUIDToDevice:
                case kAudioPlugInPropertyResourceBundle:
                    return true;
            }
            break;

        case kObjectID_Device:
            switch (address->mSelector) {
                case kAudioObjectPropertyBaseClass:
                case kAudioObjectPropertyClass:
                case kAudioObjectPropertyOwner:
                case kAudioObjectPropertyName:
                case kAudioObjectPropertyManufacturer:
                case kAudioObjectPropertyOwnedObjects:
                case kAudioDevicePropertyDeviceUID:
                case kAudioDevicePropertyModelUID:
                case kAudioDevicePropertyTransportType:
                case kAudioDevicePropertyRelatedDevices:
                case kAudioDevicePropertyClockDomain:
                case kAudioDevicePropertyDeviceIsAlive:
                case kAudioDevicePropertyDeviceIsRunning:
                case kAudioDevicePropertyDeviceCanBeDefaultDevice:
                case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
                case kAudioDevicePropertyLatency:
                case kAudioDevicePropertyStreams:
                case kAudioObjectPropertyControlList:
                case kAudioDevicePropertyNominalSampleRate:
                case kAudioDevicePropertyAvailableNominalSampleRates:
                case kAudioDevicePropertyZeroTimeStampPeriod:
                case kAudioDevicePropertySafetyOffset:
                case kAudioDevicePropertyIsHidden:
                case kAudioDevicePropertyPreferredChannelsForStereo:
                    return true;
            }
            break;

        case kObjectID_Stream:
            switch (address->mSelector) {
                case kAudioObjectPropertyBaseClass:
                case kAudioObjectPropertyClass:
                case kAudioObjectPropertyOwner:
                case kAudioObjectPropertyName:
                case kAudioStreamPropertyIsActive:
                case kAudioStreamPropertyDirection:
                case kAudioStreamPropertyTerminalType:
                case kAudioStreamPropertyStartingChannel:
                case kAudioStreamPropertyLatency:
                case kAudioStreamPropertyVirtualFormat:
                case kAudioStreamPropertyPhysicalFormat:
                case kAudioStreamPropertyAvailableVirtualFormats:
                case kAudioStreamPropertyAvailablePhysicalFormats:
                    return true;
            }
            break;
    }
    return false;
}

// ============================================================================
#pragma mark - Property Support: IsPropertySettable
// ============================================================================

static OSStatus _IsPropertySettable(AudioServerPlugInDriverRef d, AudioObjectID objectID, pid_t clientPID, const AudioObjectPropertyAddress *address, Boolean *outIsSettable)
{
    *outIsSettable = false;
    return kAudioHardwareNoError;
}

// ============================================================================
#pragma mark - Property Support: GetPropertyDataSize
// ============================================================================

static OSStatus _GetPropertyDataSize(AudioServerPlugInDriverRef d, AudioObjectID objectID, pid_t clientPID, const AudioObjectPropertyAddress *address, UInt32 qualifierDataSize, const void *qualifierData, UInt32 *outDataSize)
{
    switch (objectID) {
        case kObjectID_PlugIn:
            switch (address->mSelector) {
                case kAudioObjectPropertyBaseClass:
                case kAudioObjectPropertyClass:
                case kAudioObjectPropertyOwner:
                    *outDataSize = sizeof(AudioClassID);
                    return kAudioHardwareNoError;
                case kAudioObjectPropertyManufacturer:
                    *outDataSize = sizeof(CFStringRef);
                    return kAudioHardwareNoError;
                case kAudioObjectPropertyOwnedObjects:
                case kAudioPlugInPropertyDeviceList:
                    *outDataSize = sizeof(AudioObjectID);
                    return kAudioHardwareNoError;
                case kAudioPlugInPropertyTranslateUIDToDevice:
                    *outDataSize = sizeof(AudioObjectID);
                    return kAudioHardwareNoError;
                case kAudioPlugInPropertyResourceBundle:
                    *outDataSize = sizeof(CFStringRef);
                    return kAudioHardwareNoError;
            }
            break;

        case kObjectID_Device:
            switch (address->mSelector) {
                case kAudioObjectPropertyBaseClass:
                case kAudioObjectPropertyClass:
                case kAudioObjectPropertyOwner:
                    *outDataSize = sizeof(AudioClassID);
                    return kAudioHardwareNoError;
                case kAudioObjectPropertyName:
                case kAudioObjectPropertyManufacturer:
                case kAudioDevicePropertyDeviceUID:
                case kAudioDevicePropertyModelUID:
                    *outDataSize = sizeof(CFStringRef);
                    return kAudioHardwareNoError;
                case kAudioDevicePropertyTransportType:
                case kAudioDevicePropertyClockDomain:
                case kAudioDevicePropertyLatency:
                case kAudioDevicePropertySafetyOffset:
                case kAudioDevicePropertyZeroTimeStampPeriod:
                    *outDataSize = sizeof(UInt32);
                    return kAudioHardwareNoError;
                case kAudioDevicePropertyRelatedDevices:
                    *outDataSize = sizeof(AudioObjectID);
                    return kAudioHardwareNoError;
                case kAudioDevicePropertyDeviceIsAlive:
                case kAudioDevicePropertyDeviceIsRunning:
                case kAudioDevicePropertyDeviceCanBeDefaultDevice:
                case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
                    *outDataSize = sizeof(UInt32);
                    return kAudioHardwareNoError;
                case kAudioDevicePropertyStreams:
                case kAudioObjectPropertyOwnedObjects:
                    *outDataSize = sizeof(AudioObjectID);
                    return kAudioHardwareNoError;
                case kAudioObjectPropertyControlList:
                    *outDataSize = 0;
                    return kAudioHardwareNoError;
                case kAudioDevicePropertyNominalSampleRate:
                    *outDataSize = sizeof(Float64);
                    return kAudioHardwareNoError;
                case kAudioDevicePropertyAvailableNominalSampleRates:
                    *outDataSize = sizeof(AudioValueRange);
                    return kAudioHardwareNoError;
                case kAudioDevicePropertyIsHidden:
                    *outDataSize = sizeof(UInt32);
                    return kAudioHardwareNoError;
                case kAudioDevicePropertyPreferredChannelsForStereo:
                    *outDataSize = 2 * sizeof(UInt32);
                    return kAudioHardwareNoError;
            }
            break;

        case kObjectID_Stream:
            switch (address->mSelector) {
                case kAudioObjectPropertyBaseClass:
                case kAudioObjectPropertyClass:
                case kAudioObjectPropertyOwner:
                    *outDataSize = sizeof(AudioClassID);
                    return kAudioHardwareNoError;
                case kAudioObjectPropertyName:
                    *outDataSize = sizeof(CFStringRef);
                    return kAudioHardwareNoError;
                case kAudioStreamPropertyIsActive:
                case kAudioStreamPropertyDirection:
                case kAudioStreamPropertyTerminalType:
                case kAudioStreamPropertyStartingChannel:
                case kAudioStreamPropertyLatency:
                    *outDataSize = sizeof(UInt32);
                    return kAudioHardwareNoError;
                case kAudioStreamPropertyVirtualFormat:
                case kAudioStreamPropertyPhysicalFormat:
                    *outDataSize = sizeof(AudioStreamBasicDescription);
                    return kAudioHardwareNoError;
                case kAudioStreamPropertyAvailableVirtualFormats:
                case kAudioStreamPropertyAvailablePhysicalFormats:
                    *outDataSize = sizeof(AudioStreamRangedDescription);
                    return kAudioHardwareNoError;
            }
            break;
    }

    *outDataSize = 0;
    return kAudioHardwareUnknownPropertyError;
}

// ============================================================================
#pragma mark - Property Support: GetPropertyData
// ============================================================================

static AudioStreamBasicDescription _getStreamFormat(void)
{
    AudioStreamBasicDescription fmt = {};
    fmt.mSampleRate = kDevice_SampleRate;
    fmt.mFormatID = kAudioFormatLinearPCM;
    fmt.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;
    fmt.mBytesPerPacket = kDevice_BytesPerFrame;
    fmt.mFramesPerPacket = 1;
    fmt.mBytesPerFrame = kDevice_BytesPerFrame;
    fmt.mChannelsPerFrame = kDevice_NumChannels;
    fmt.mBitsPerChannel = kDevice_BitsPerChannel;
    return fmt;
}

static OSStatus _GetPropertyData(AudioServerPlugInDriverRef d, AudioObjectID objectID, pid_t clientPID, const AudioObjectPropertyAddress *address, UInt32 qualifierDataSize, const void *qualifierData, UInt32 inDataSize, UInt32 *outDataSize, void *outData)
{
    // ------ PLUGIN ------
    if (objectID == kObjectID_PlugIn) {
        switch (address->mSelector) {
            case kAudioObjectPropertyBaseClass:
                *outDataSize = sizeof(AudioClassID);
                *((AudioClassID *)outData) = kAudioObjectClassID;
                return kAudioHardwareNoError;

            case kAudioObjectPropertyClass:
                *outDataSize = sizeof(AudioClassID);
                *((AudioClassID *)outData) = kAudioPlugInClassID;
                return kAudioHardwareNoError;

            case kAudioObjectPropertyOwner:
                *outDataSize = sizeof(AudioObjectID);
                *((AudioObjectID *)outData) = kAudioObjectUnknown;
                return kAudioHardwareNoError;

            case kAudioObjectPropertyManufacturer:
                *outDataSize = sizeof(CFStringRef);
                *((CFStringRef *)outData) = CFSTR(kDevice_Manufacturer);
                return kAudioHardwareNoError;

            case kAudioObjectPropertyOwnedObjects:
            case kAudioPlugInPropertyDeviceList:
                *outDataSize = sizeof(AudioObjectID);
                *((AudioObjectID *)outData) = kObjectID_Device;
                return kAudioHardwareNoError;

            case kAudioPlugInPropertyTranslateUIDToDevice: {
                CFStringRef uid = *((CFStringRef *)qualifierData);
                *outDataSize = sizeof(AudioObjectID);
                if (CFStringCompare(uid, CFSTR(kDevice_UID), 0) == kCFCompareEqualTo) {
                    *((AudioObjectID *)outData) = kObjectID_Device;
                } else {
                    *((AudioObjectID *)outData) = kAudioObjectUnknown;
                }
                return kAudioHardwareNoError;
            }

            case kAudioPlugInPropertyResourceBundle:
                *outDataSize = sizeof(CFStringRef);
                *((CFStringRef *)outData) = CFSTR("");
                return kAudioHardwareNoError;
        }
    }

    // ------ DEVICE ------
    if (objectID == kObjectID_Device) {
        switch (address->mSelector) {
            case kAudioObjectPropertyBaseClass:
                *outDataSize = sizeof(AudioClassID);
                *((AudioClassID *)outData) = kAudioObjectClassID;
                return kAudioHardwareNoError;

            case kAudioObjectPropertyClass:
                *outDataSize = sizeof(AudioClassID);
                *((AudioClassID *)outData) = kAudioDeviceClassID;
                return kAudioHardwareNoError;

            case kAudioObjectPropertyOwner:
                *outDataSize = sizeof(AudioObjectID);
                *((AudioObjectID *)outData) = kObjectID_PlugIn;
                return kAudioHardwareNoError;

            case kAudioObjectPropertyName:
                *outDataSize = sizeof(CFStringRef);
                *((CFStringRef *)outData) = CFSTR(kDevice_Name);
                return kAudioHardwareNoError;

            case kAudioObjectPropertyManufacturer:
                *outDataSize = sizeof(CFStringRef);
                *((CFStringRef *)outData) = CFSTR(kDevice_Manufacturer);
                return kAudioHardwareNoError;

            case kAudioDevicePropertyDeviceUID:
                *outDataSize = sizeof(CFStringRef);
                *((CFStringRef *)outData) = CFSTR(kDevice_UID);
                return kAudioHardwareNoError;

            case kAudioDevicePropertyModelUID:
                *outDataSize = sizeof(CFStringRef);
                *((CFStringRef *)outData) = CFSTR(kDevice_ModelUID);
                return kAudioHardwareNoError;

            case kAudioDevicePropertyTransportType:
                *outDataSize = sizeof(UInt32);
                *((UInt32 *)outData) = kAudioDeviceTransportTypeVirtual;
                return kAudioHardwareNoError;

            case kAudioDevicePropertyRelatedDevices:
                *outDataSize = sizeof(AudioObjectID);
                *((AudioObjectID *)outData) = kObjectID_Device;
                return kAudioHardwareNoError;

            case kAudioDevicePropertyClockDomain:
                *outDataSize = sizeof(UInt32);
                *((UInt32 *)outData) = 0;
                return kAudioHardwareNoError;

            case kAudioDevicePropertyDeviceIsAlive:
                *outDataSize = sizeof(UInt32);
                *((UInt32 *)outData) = 1;
                return kAudioHardwareNoError;

            case kAudioDevicePropertyDeviceIsRunning:
                *outDataSize = sizeof(UInt32);
                *((UInt32 *)outData) = gDriverState.isRunning ? 1 : 0;
                return kAudioHardwareNoError;

            case kAudioDevicePropertyDeviceCanBeDefaultDevice:
                *outDataSize = sizeof(UInt32);
                // Only advertise as default for input (microphone) scope
                if (address->mScope == kAudioObjectPropertyScopeInput || address->mScope == kAudioObjectPropertyScopeGlobal) {
                    *((UInt32 *)outData) = 1;
                } else {
                    *((UInt32 *)outData) = 0;
                }
                return kAudioHardwareNoError;

            case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
                *outDataSize = sizeof(UInt32);
                *((UInt32 *)outData) = 0;
                return kAudioHardwareNoError;

            case kAudioDevicePropertyLatency:
                *outDataSize = sizeof(UInt32);
                *((UInt32 *)outData) = 0;
                return kAudioHardwareNoError;

            case kAudioDevicePropertySafetyOffset:
                *outDataSize = sizeof(UInt32);
                *((UInt32 *)outData) = 0;
                return kAudioHardwareNoError;

            case kAudioDevicePropertyStreams:
            case kAudioObjectPropertyOwnedObjects:
                // Only return stream for input scope
                if (address->mScope == kAudioObjectPropertyScopeInput || address->mScope == kAudioObjectPropertyScopeGlobal) {
                    *outDataSize = sizeof(AudioObjectID);
                    *((AudioObjectID *)outData) = kObjectID_Stream;
                } else {
                    *outDataSize = 0;
                }
                return kAudioHardwareNoError;

            case kAudioObjectPropertyControlList:
                *outDataSize = 0;
                return kAudioHardwareNoError;

            case kAudioDevicePropertyNominalSampleRate:
                *outDataSize = sizeof(Float64);
                *((Float64 *)outData) = kDevice_SampleRate;
                return kAudioHardwareNoError;

            case kAudioDevicePropertyAvailableNominalSampleRates: {
                AudioValueRange range = { kDevice_SampleRate, kDevice_SampleRate };
                *outDataSize = sizeof(AudioValueRange);
                memcpy(outData, &range, sizeof(AudioValueRange));
                return kAudioHardwareNoError;
            }

            case kAudioDevicePropertyZeroTimeStampPeriod:
                *outDataSize = sizeof(UInt32);
                *((UInt32 *)outData) = kDevice_RingBufferSize;
                return kAudioHardwareNoError;

            case kAudioDevicePropertyIsHidden:
                *outDataSize = sizeof(UInt32);
                *((UInt32 *)outData) = 0;  // Not hidden
                return kAudioHardwareNoError;

            case kAudioDevicePropertyPreferredChannelsForStereo: {
                UInt32 channels[2] = { 1, 1 };  // Mono device, both channels map to 1
                *outDataSize = 2 * sizeof(UInt32);
                memcpy(outData, channels, 2 * sizeof(UInt32));
                return kAudioHardwareNoError;
            }
        }
    }

    // ------ STREAM ------
    if (objectID == kObjectID_Stream) {
        switch (address->mSelector) {
            case kAudioObjectPropertyBaseClass:
                *outDataSize = sizeof(AudioClassID);
                *((AudioClassID *)outData) = kAudioObjectClassID;
                return kAudioHardwareNoError;

            case kAudioObjectPropertyClass:
                *outDataSize = sizeof(AudioClassID);
                *((AudioClassID *)outData) = kAudioStreamClassID;
                return kAudioHardwareNoError;

            case kAudioObjectPropertyOwner:
                *outDataSize = sizeof(AudioObjectID);
                *((AudioObjectID *)outData) = kObjectID_Device;
                return kAudioHardwareNoError;

            case kAudioObjectPropertyName:
                *outDataSize = sizeof(CFStringRef);
                *((CFStringRef *)outData) = CFSTR("Test Camera Audio Input");
                return kAudioHardwareNoError;

            case kAudioStreamPropertyIsActive:
                *outDataSize = sizeof(UInt32);
                *((UInt32 *)outData) = 1;
                return kAudioHardwareNoError;

            case kAudioStreamPropertyDirection:
                *outDataSize = sizeof(UInt32);
                *((UInt32 *)outData) = 1;  // 1 = input (microphone)
                return kAudioHardwareNoError;

            case kAudioStreamPropertyTerminalType:
                *outDataSize = sizeof(UInt32);
                *((UInt32 *)outData) = kAudioStreamTerminalTypeMicrophone;
                return kAudioHardwareNoError;

            case kAudioStreamPropertyStartingChannel:
                *outDataSize = sizeof(UInt32);
                *((UInt32 *)outData) = 1;
                return kAudioHardwareNoError;

            case kAudioStreamPropertyLatency:
                *outDataSize = sizeof(UInt32);
                *((UInt32 *)outData) = 0;
                return kAudioHardwareNoError;

            case kAudioStreamPropertyVirtualFormat:
            case kAudioStreamPropertyPhysicalFormat: {
                AudioStreamBasicDescription fmt = _getStreamFormat();
                *outDataSize = sizeof(AudioStreamBasicDescription);
                memcpy(outData, &fmt, sizeof(AudioStreamBasicDescription));
                return kAudioHardwareNoError;
            }

            case kAudioStreamPropertyAvailableVirtualFormats:
            case kAudioStreamPropertyAvailablePhysicalFormats: {
                AudioStreamBasicDescription fmt = _getStreamFormat();
                AudioStreamRangedDescription ranged = {};
                ranged.mFormat = fmt;
                ranged.mSampleRateRange.mMinimum = kDevice_SampleRate;
                ranged.mSampleRateRange.mMaximum = kDevice_SampleRate;
                *outDataSize = sizeof(AudioStreamRangedDescription);
                memcpy(outData, &ranged, sizeof(AudioStreamRangedDescription));
                return kAudioHardwareNoError;
            }
        }
    }

    return kAudioHardwareUnknownPropertyError;
}

// ============================================================================
#pragma mark - Property Support: SetPropertyData
// ============================================================================

static OSStatus _SetPropertyData(AudioServerPlugInDriverRef d, AudioObjectID objectID, pid_t clientPID, const AudioObjectPropertyAddress *address, UInt32 qualifierDataSize, const void *qualifierData, UInt32 inDataSize, const void *inData)
{
    return kAudioHardwareNoError;
}

// ============================================================================
#pragma mark - IO Operations
// ============================================================================

static void _openSharedState(void)
{
    if (gDriverState.stateFD >= 0) return;

    gDriverState.stateFD = open(kStateFilePath, O_RDONLY);
    if (gDriverState.stateFD >= 0) {
        gDriverState.sharedState = (struct AudioDriverState *)mmap(
            NULL, sizeof(struct AudioDriverState),
            PROT_READ, MAP_SHARED,
            gDriverState.stateFD, 0
        );
        if (gDriverState.sharedState == MAP_FAILED) {
            gDriverState.sharedState = NULL;
            close(gDriverState.stateFD);
            gDriverState.stateFD = -1;
        }
    }
}

static OSStatus _StartIO(AudioServerPlugInDriverRef d, AudioObjectID objectID, UInt32 clientID)
{
    pthread_mutex_lock(&gDriverState.mutex);

    gDriverState.isRunning = true;
    gDriverState.ioCounter = 0;
    gDriverState.sampleTime = 0;
    gDriverState.anchorHostTime = mach_absolute_time();
    gDriverState.phase = 0;
    gAudioCtx.phase = 0;
    gAudioCtx.streamTime = 0;
    gAudioCtx.sampleRate = kDevice_SampleRate;
    gAudioCtx.patternID = kPattern_BouncingBall;

    // Try to open shared state file
    _openSharedState();

    pthread_mutex_unlock(&gDriverState.mutex);
    return kAudioHardwareNoError;
}

static OSStatus _StopIO(AudioServerPlugInDriverRef d, AudioObjectID objectID, UInt32 clientID)
{
    pthread_mutex_lock(&gDriverState.mutex);

    gDriverState.isRunning = false;

    if (gDriverState.sharedState) {
        munmap(gDriverState.sharedState, sizeof(struct AudioDriverState));
        gDriverState.sharedState = NULL;
    }
    if (gDriverState.stateFD >= 0) {
        close(gDriverState.stateFD);
        gDriverState.stateFD = -1;
    }

    pthread_mutex_unlock(&gDriverState.mutex);
    return kAudioHardwareNoError;
}

static OSStatus _GetZeroTimeStamp(AudioServerPlugInDriverRef d, AudioObjectID objectID, UInt32 clientID, Float64 *outSampleTime, UInt64 *outHostTime, UInt64 *outSeed)
{
    // Convert host ticks to nanoseconds
    static mach_timebase_info_data_t timebase = { 0, 0 };
    if (timebase.denom == 0) {
        mach_timebase_info(&timebase);
    }

    UInt64 currentHostTime = mach_absolute_time();
    UInt64 elapsedNanos = (currentHostTime - gDriverState.anchorHostTime) * timebase.numer / timebase.denom;
    Float64 elapsedSeconds = (Float64)elapsedNanos / 1000000000.0;
    Float64 elapsedSamples = elapsedSeconds * kDevice_SampleRate;

    // Align to ring buffer boundaries
    UInt64 cycleCount = (UInt64)(elapsedSamples / kDevice_RingBufferSize);
    *outSampleTime = (Float64)(cycleCount * kDevice_RingBufferSize);
    *outHostTime = gDriverState.anchorHostTime + (UInt64)(cycleCount * kDevice_RingBufferSize / kDevice_SampleRate * 1000000000.0 * timebase.denom / timebase.numer);
    *outSeed = 1;

    return kAudioHardwareNoError;
}

static OSStatus _WillDoIOOperation(AudioServerPlugInDriverRef d, AudioObjectID objectID, UInt32 clientID, UInt32 operationID, Boolean *outWillDo, Boolean *outWillDoInPlace)
{
    *outWillDo = (operationID == kAudioServerPlugInIOOperationReadInput);
    *outWillDoInPlace = true;
    return kAudioHardwareNoError;
}

static OSStatus _BeginIOOperation(AudioServerPlugInDriverRef d, AudioObjectID objectID, UInt32 clientID, UInt32 operationID, UInt32 ioBufferFrameSize, const AudioServerPlugInIOCycleInfo *ioCycleInfo)
{
    return kAudioHardwareNoError;
}

static OSStatus _DoIOOperation(AudioServerPlugInDriverRef d, AudioObjectID objectID, AudioObjectID streamID, UInt32 clientID, UInt32 operationID, UInt32 ioBufferFrameSize, const AudioServerPlugInIOCycleInfo *ioCycleInfo, void *ioMainBuffer, void *ioSecondaryBuffer)
{
    if (operationID != kAudioServerPlugInIOOperationReadInput) {
        return kAudioHardwareNoError;
    }

    float *buffer = (float *)ioMainBuffer;

    // Read shared state if available
    if (gDriverState.sharedState) {
        gAudioCtx.patternID = gDriverState.sharedState->patternID;
    }

    // Update time tracking
    gAudioCtx.streamTime = gDriverState.sampleTime / kDevice_SampleRate;

    // Generate audio
    generatePatternAudio(buffer, ioBufferFrameSize, &gAudioCtx);

    // Advance sample position
    gDriverState.sampleTime += (Float64)ioBufferFrameSize;

    return kAudioHardwareNoError;
}

static OSStatus _EndIOOperation(AudioServerPlugInDriverRef d, AudioObjectID objectID, UInt32 clientID, UInt32 operationID, UInt32 ioBufferFrameSize, const AudioServerPlugInIOCycleInfo *ioCycleInfo)
{
    return kAudioHardwareNoError;
}

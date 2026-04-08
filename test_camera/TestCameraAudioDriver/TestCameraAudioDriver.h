//
//  TestCameraAudioDriver.h
//  TestCameraAudioDriver
//
//  CoreAudio HAL plugin that creates a virtual microphone ("Test Camera Audio")
//  for A/V sync testing. Generates tone bursts, continuous tones, or silence
//  matching the currently selected video test pattern.
//

#ifndef TestCameraAudioDriver_h
#define TestCameraAudioDriver_h

#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <math.h>
#include <string.h>
#include <stdio.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

// ============================================================================
// Constants
// ============================================================================

#define kPlugIn_BundleID        "com.yepher.vidtiming.testcamera.audiodriver"
#define kDevice_UID             "TestCameraAudioDevice_UID"
#define kDevice_ModelUID        "TestCameraAudioModel_UID"
#define kDevice_Name            "Test Camera Audio"
#define kDevice_Manufacturer    "Yepher"

// Object IDs
#define kObjectID_PlugIn            ((AudioObjectID)kAudioObjectPlugInObject)
#define kObjectID_Device            ((AudioObjectID)2)
#define kObjectID_Stream            ((AudioObjectID)3)

// Audio format
#define kDevice_SampleRate      48000.0
#define kDevice_NumChannels     1
#define kDevice_BitsPerChannel  32
#define kDevice_BytesPerFrame   (kDevice_NumChannels * (kDevice_BitsPerChannel / 8))
#define kDevice_RingBufferSize  16384  // frames per IO cycle

// Pattern types (must match Swift PatternType enum)
enum PatternID {
    kPattern_BouncingBall = 0,
    kPattern_SMPTEBars    = 1,
    kPattern_GridChart     = 2,
    kPattern_Countdown    = 3
};

// ============================================================================
// Shared state struct (read via mmap from /tmp/com.testcamera.audio.state)
// ============================================================================

struct AudioDriverState {
    uint32_t    patternID;      // PatternID enum
    double      streamTime;     // Current time in seconds
    uint32_t    frameCounter;   // Video frame counter
    uint32_t    sequence;       // Incremented on each update
    uint32_t    enableAudio;    // 1 = generate audio, 0 = silence
};

// ============================================================================
// Driver instance data
// ============================================================================

struct TestCameraAudioDriverState {
    // Reference counting
    UInt32 refCount;

    // Host interface
    AudioServerPlugInHostRef host;

    // IO state
    Boolean isRunning;
    UInt64 ioCounter;           // Incremented each IO cycle
    Float64 sampleTime;         // Current sample position
    UInt64 anchorHostTime;      // Host time at IO start

    // Audio generation
    double phase;               // Phase accumulator for tone generation
    int currentPattern;         // Current pattern being generated
    double audioTime;           // Audio time tracking

    // Shared state
    int stateFD;                // File descriptor for mmap
    struct AudioDriverState *sharedState;  // mmap'd state from camera extension

    // Mutex for thread safety
    pthread_mutex_t mutex;
};

// ============================================================================
// Plugin factory function (entry point)
// ============================================================================

extern "C" void* TestCameraAudioDriverFactory(CFAllocatorRef allocator, CFUUIDRef requestedTypeUUID);

#endif /* TestCameraAudioDriver_h */

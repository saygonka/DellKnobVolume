import Foundation
import IOKit.hid
import CoreAudio
import AudioToolbox

// MARK: - Volume control via CoreAudio
enum Volume {
    private static func defaultOutputDeviceID() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil, &size, &deviceID
        )
        if status != noErr {
            fputs("Error: failed to fetch default output device (\(status)).\n", stderr)
        }
        return deviceID
    }

    static func get() -> Float {
        let deviceID = defaultOutputDeviceID()
        var vol = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)

        // 1) Try Virtual Main Volume first
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &vol)
        if status == noErr { return Float(vol) }

        // 2) Fallback: channel 1
        addr.mSelector = kAudioDevicePropertyVolumeScalar
        addr.mElement  = 1
        status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &vol)
        if status == noErr { return Float(vol) }

        // 3) Fallback: channel 2
        addr.mElement  = 2
        status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &vol)
        if status == noErr { return Float(vol) }

        return 0.5 // default value
    }

    static func set(_ value: Float) {
        let deviceID = defaultOutputDeviceID()
        let v = max(0.0, min(1.0, value))
        var vol = Float32(v)
        let size = UInt32(MemoryLayout<Float32>.size)

        // 1) Try Virtual Main Volume first
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var status = AudioObjectSetPropertyData(deviceID, &addr, 0, nil, size, &vol)
        if status == noErr { return }

        // 2) Fallback: channel 1
        addr.mSelector = kAudioDevicePropertyVolumeScalar
        addr.mElement  = 1
        status = AudioObjectSetPropertyData(deviceID, &addr, 0, nil, size, &vol)
        if status == noErr { return }

        // 3) Fallback: channel 2
        addr.mElement  = 2
        _ = AudioObjectSetPropertyData(deviceID, &addr, 0, nil, size, &vol)
    }

    static func delta(_ step: Float) {
        set(get() + step)
    }

    static func toggleMute() {
        let deviceID = defaultOutputDeviceID()
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var isMuted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &isMuted)
        if status == noErr {
            var newVal: UInt32 = isMuted == 0 ? 1 : 0
            _ = AudioObjectSetPropertyData(deviceID, &addr, 0, nil, size, &newVal)
        }
    }
}

// MARK: - HID listener for Consumer Control (Volume Up/Down/Mute)
final class HIDListener {
    private let manager: IOHIDManager
    private let step: Float

    init(step: Float = 0.05) {
        self.step = step
        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func start() {
        let matches: [[String: Any]] = [
            [
                kIOHIDDeviceUsagePageKey as String: kHIDPage_Consumer,
                kIOHIDDeviceUsageKey as String: kHIDUsage_Csmr_ConsumerControl
            ]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterInputValueCallback(
            manager,
            { context, result, _, value in
                guard result == kIOReturnSuccess, let context else { return }
                let listener = Unmanaged<HIDListener>.fromOpaque(context).takeUnretainedValue()
                listener.handleInputValue(value)
            },
            context
        )
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        let openStatus = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openStatus != kIOReturnSuccess {
            fputs("Error: unable to open IOHIDManager (status \(openStatus)).\n", stderr)
        } else {
            print("Running. Rotate the knob to change the volume (5% step).")
        }
    }

    private func handleInputValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let rawValue = IOHIDValueGetIntegerValue(value)

        switch (usagePage, usage) {
        case (UInt32(kHIDPage_Consumer), UInt32(kHIDUsage_Csmr_VolumeIncrement)):
            guard rawValue != 0 else { return }
            Volume.delta(step)
        case (UInt32(kHIDPage_Consumer), UInt32(kHIDUsage_Csmr_VolumeDecrement)):
            guard rawValue != 0 else { return }
            Volume.delta(-step)
        case (UInt32(kHIDPage_Consumer), UInt32(kHIDUsage_Csmr_Mute)):
            guard rawValue != 0 else { return }
            Volume.toggleMute()
        case (UInt32(kHIDPage_Consumer), UInt32(224)):
            let delta = Float(rawValue) * step
            guard delta != 0 else { return }
            Volume.delta(delta)
        case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Dial)):
            if rawValue > 0 {
                Volume.delta(step)
            } else if rawValue < 0 {
                Volume.delta(-step)
            }
        default:
#if DEBUG
            print("Unhandled HID event - usagePage: \(usagePage), usage: \(usage), value: \(rawValue)")
#endif
        }
    }
}

// MARK: - Main
let listener = HIDListener(step: 0.05)
listener.start()
CFRunLoopRun()

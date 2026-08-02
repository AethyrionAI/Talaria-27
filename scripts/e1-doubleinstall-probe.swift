// E1 — deliberate double-install probe (device-list §E1, OPEN_ITEMS #198/#128).
//
// THE QUESTION: does the iOS 27 error-returning tap installer THROW on a
// double-install, where the deprecated `installTap` RAISED an uncatchable
// Objective-C exception (`AVAEGraphNode CreateRecordingTap: nullptr == Tap()`,
// the #128 device crash of 2026-07-17)?
//
// WHY THIS IS NOT A TEST: if the successor still raises, it takes the host
// process down rather than failing an assertion. As an XCTest that costs a green
// suite and teaches nothing. As a standalone binary under `simctl spawn`, the
// process dying IS the answer and costs nothing.
//
// READING THE RESULT:
//   "E1: THREW"    -> recoverable. The #198 migration rationale is CONFIRMED.
//   "E1: NO THROW" -> the second install silently succeeded; the invariant is
//                     not enforced by the API at all.
//   process dies   -> it still RAISES. The migration did NOT make this
//                     survivable and #198's rationale is FALSIFIED.
//
// RESULT ON FIRST RUN, 2026-08-01 (iOS 27.0 sim 24A5390f, two identical runs):
//   mainMixer THREW -- Code=-10863 {false condition=nullptr == Tap()}
//   ...which is the EXACT condition string from #128's 2026-07-17 device crash.
//   inputNode's first install also threw, on the sim's degenerate rate=0.0
//   format -- #82's wedge shape, likewise now reported rather than raised.
//
// RE-RUN THIS AFTER ANY SDK BUMP. `__installTap` is the refined-for-Swift
// spelling awaiting an AVFAudio overlay; when the overlay lands the call site
// changes, and this probe is how you learn whether the BEHAVIOUR changed with
// it. It lives outside project.yml's source paths, so it needs no xcodegen.
//
//   DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer \
//     xcrun -sdk iphonesimulator swiftc \
//     -target arm64-apple-ios27.0-simulator \
//     scripts/e1-doubleinstall-probe.swift -o /tmp/e1probe
//   DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer \
//     xcrun simctl spawn <SIM-UDID> /tmp/e1probe

import AVFAudio
import Foundation

enum AudioNodeTapShim {
    // Same spelling the app uses (Talaria/Services/Support/TalkSessionRules.swift).
    static func install(on node: AVAudioNode, bus: AVAudioNodeBus = 0,
                        bufferSize: AVAudioFrameCount, format: AVAudioFormat?,
                        block: @escaping AVAudioNodeTapBlock) throws {
        try node.__installTap(onBus: bus, bufferSize: bufferSize,
                              format: format, error: (), block: block)
    }
}

func probe(_ label: String, _ node: AVAudioNode) {
    let fmt = node.outputFormat(forBus: 0)
    print("E1: --- \(label) — format rate=\(fmt.sampleRate) ch=\(fmt.channelCount)")
    let block: AVAudioNodeTapBlock = { _, _ in }

    // First install: expected to succeed. If THIS throws, the probe is
    // inconclusive — report and bail rather than pretending the second call
    // measured anything.
    do {
        try AudioNodeTapShim.install(on: node, bufferSize: 1024, format: fmt, block: block)
        print("E1: \(label) first install OK")
    } catch {
        print("E1: \(label) INCONCLUSIVE — first install threw: \(error)")
        return
    }

    // Second install on the SAME node + bus, with NO intervening removeTap.
    // This is exactly the state #128's adjacency invariant exists to prevent.
    print("E1: \(label) attempting SECOND install (no removeTap) ...")
    do {
        try AudioNodeTapShim.install(on: node, bufferSize: 1024, format: fmt, block: block)
        print("E1: \(label) NO THROW — the second install was accepted")
    } catch {
        print("E1: \(label) THREW — \(error)")
    }
    node.removeTap(onBus: 0)
}

print("E1: probe start — \(ProcessInfo.processInfo.operatingSystemVersionString)")

let engine = AVAudioEngine()

// mainMixerNode needs no microphone permission. It exercises the same
// AVAudioNode tap machinery, so it isolates "does the installer throw" from
// "can this host capture audio".
probe("mainMixer", engine.mainMixerNode)

// inputNode is the node #128 actually crashed on. On a simulator this may have a
// degenerate format (0 Hz / 0 ch) with no mic — reported, not hidden, because a
// degenerate format is #82's shape and would make the result mean something else.
probe("inputNode", engine.inputNode)

print("E1: probe end — reached the end WITHOUT the process being raised out of")

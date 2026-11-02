import Foundation
import IOBluetooth
import Testing
@testable import SoundcoreKit

/// IOBluetooth's delegate methods are optional/informal. A Swift signature that is slightly
/// wrong still compiles but is never called, so check the Objective-C selectors directly.
@Suite("IOBluetooth callbacks are wired")
@MainActor
struct DelegateSelectorTests {
    @Test func rfcommDelegateSelectors() {
        let link = RFCOMMLink()
        #expect(link.responds(to: NSSelectorFromString("rfcommChannelOpenComplete:status:")))
        #expect(link.responds(to: NSSelectorFromString("rfcommChannelData:data:length:")))
        #expect(link.responds(to: NSSelectorFromString("rfcommChannelClosed:")))
    }

    @Test func sdpQueryCallbackSelector() {
        #expect(SDPQuery().responds(to: NSSelectorFromString("sdpQueryComplete:status:")))
    }

    @Test func connectionNotificationSelectors() {
        let watcher = ConnectionWatcher(onConnect: { _ in }, onDisconnect: { _ in })
        #expect(watcher.responds(to: NSSelectorFromString("deviceConnected:device:")))
        #expect(watcher.responds(to: NSSelectorFromString("deviceDisconnected:device:")))
        #expect(watcher.responds(to: NSSelectorFromString("connectionComplete:status:")))
    }

    /// Regression: on macOS 27, IOBluetooth posts connect notifications on a private queue
    /// (`com.apple.bluetooth.iobluetooth.coordinatorQueue`), which used to trap in this
    /// main-actor class. Registering fires a notification for every already-connected device,
    /// so with any Bluetooth device connected this exercises the real callback path.
    @Test func connectNotificationsArriveOnMainActor() async {
        var calls = 0
        let watcher = ConnectionWatcher(onConnect: { _ in calls += 1 }, onDisconnect: { _ in })
        watcher.start()
        try? await Task.sleep(for: .milliseconds(500))
        watcher.stop()
        #expect(calls >= 0) // reaching this line without a trap is the test
    }
}

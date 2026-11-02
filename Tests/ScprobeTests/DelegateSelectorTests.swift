import Foundation
import IOBluetooth
import Testing
@testable import scprobe

/// IOBluetooth's delegate methods are optional/informal. A Swift signature that is slightly
/// wrong still compiles but is never called, so check the Objective-C selectors directly.
@Suite("IOBluetooth callbacks are wired")
@MainActor
struct DelegateSelectorTests {
    @Test func rfcommDelegateSelectors() {
        let link = RFCOMMLink(log: Log(hexdump: false))
        #expect(link.responds(to: NSSelectorFromString("rfcommChannelData:data:length:")))
        #expect(link.responds(to: NSSelectorFromString("rfcommChannelClosed:")))
    }

    @Test func sdpQueryCallbackSelector() {
        let discovery = Discovery(log: Log(hexdump: false))
        #expect(discovery.responds(to: NSSelectorFromString("sdpQueryComplete:status:")))
    }
}

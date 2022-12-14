//
//  BitcoinsUITests.swift
//  BitcoinsUITests
//
//  Created by SukPoet on 2022/10/20.
//

import XCTest

final class BitcoinsUITests: XCTestCase {
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        try super.setUpWithError()
        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false
        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    /**
     I tried to write UI test, but everytime I click the red record button at the bottom of the editor window to record my interactions as test commands, the test crashes. Xcode reports an error infomation as bellow:
     Thread 1: "[<_UINavigationBarContentViewLayout 0x7f8954f20830> valueForUndefinedKey:]: this class is not key value coding-compliant for the key inlineTitleView."
     I googled it. I found that it is a common issue on Xcode 14. https://developer.apple.com/forums/thread/712240
     
     https://stackoverflow.com/questions/73350251/xcode-14-beta-5-throws-an-exception
     This is a bug in Xcode 14. Other users have reported it here: https://developer.apple.com/forums/thread/712240
     Initially, the issue was reported in Xcode 14 betas, but the bug was never fixed, and now, here we are. I reproduce the issue in the official release of Xcode 14.0.1. */
    
    func testExample() throws {
        // UI tests must launch the application that they test.
        // Use recording to get started writing UI tests.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }
    
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}

#!/bin/sh

set -e

SDK="/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
TARG="arm64-apple-ios10"

swiftc *.swift -sdk "${SDK}" -target "${TARG}" -o cometblue

echo cometblue compiled! Copy it to iOS and use \'ldid -S cometblue\' to sign
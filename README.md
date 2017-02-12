<img src="http://i.imgur.com/0ksj7Gh.png" alt="SwiftShield logo" height="140" >
# Swift Obfuscator

[![GitHub release](https://img.shields.io/github/tag/rockbruno/swiftshield.svg)](https://github.com/rockbruno/swiftshield/releases)
[![GitHub license](https://img.shields.io/badge/license-MIT-lightgrey.svg)](https://raw.githubusercontent.com/rockbruno/swiftshield/master/LICENSE)

SwiftShield is a tool that generates irreversible, encrypted names for your Swift project's classes, structs and protocols (including your Pods and Storyboards) in order to protect your app from tools that reverse engineer iOS/macOS apps, like class-dump and Cycript.
For example, after running SwiftShield, the following class:
```swift
class EncryptedVideoPlayer: DecryptionProtocol {
  func start() {
    let vc = ImportantDecryptingController()
    vc.start()
  }
}
```
becomes:
```swift
class djjck3KDxjs04tgbvb: djdj3ocnC38nid {
  func start() {
    let vc = aAAAa2nc0dfmDssf()
    vc.start()
  }
}
```


## How do I deal with crash logs / analytics if my project uses SwiftShield?

After succesfully encrypting your project, SwiftShield generates a `conversionMap.txt` file with all the changes it made to your project, allowing you to pinpoint what an encrypted class really is.
````
//
//  SwiftShield
//  Conversion Map
//

Classes:

ViewController ===> YytSIcFnBAqTAyR
AppDelegate ===> uJXJkhVbwdQGNhh
SuperImportantClassThatShouldBeHidden ===> GDqKGsHjJsWQzdq
````


## Requirements

1. Xcode command-line tools
2. No logic based on class names, like loading `MyClass.xib` because `type(of:self)` is `'MyClass'`.
2. Swift 3.0 (untested on other versions, but could work)
3. Xcode 8.1 (untested on other versions, but could work)
4. No Objective-C classes that call Swift methods (untested, but could work. Swift classes that call Objective-C methods are fine)


## Installation

**Warning:** SwiftShield **irreversibly overwrites** all of your .swift files. Ideally, you should have it run only on your CI server, and on release builds.

Download the [latest release](https://github.com/rockbruno/swiftshield/releases) from this repository and [click here](https://github.com/rockbruno/swiftshield/blob/master/USAGE.md) to see how to setup SwiftShield.


## Exceptions

SwiftShield will not obfuscate:

1. Module classes that are named after default classes, like `class String`.
2. Classes that are named after their own modules, like `class SwiftyStoreKit` inside module `SwiftyStoreKit`

Struct and Protocol obfuscations are currently disabled due to massive compile times. They will be back soon.


## Next steps

SwiftShield is new, and even though it works, it takes quite some time to do so. It works by obfuscating your classes' declarations and then triggering a build. This build will fail, revealing the location of where the classes are being used, which then are accessed and obfuscated. The process is repeated until the project builds succesfully. Unfortunately, the Swift compiler sometimes doesn't show all errors at once, needing dozens of compiles in order to completely obfuscate a target.

The correct way of doing this is giving SwiftShield a complete understading of Swift (like it already has regarding class declarations), so files can be obfuscated in a single go. This already works rather well, but Swift's Module's are the prime reason why this isn't released yet. If you want to help, you can check it out at the `manual-parsing-obfuscation` branch.

For this branch, the next steps will be obfuscating method names and module names.


## License

SwiftShield is released under the MIT license. See LICENSE for details.

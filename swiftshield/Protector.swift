//
//  Protect.swift
//  swiftprotector
//
//  Created by Bruno Rocha on 1/18/17.
//  Copyright © 2017 Bruno Rocha. All rights reserved.
//

import Foundation

private let comments = "(?:\\/\\/)|(?:\\/\\*)|(?:\\*\\/)"
private let words = "[a-zA-Z0-9]{1,99}"
private let quotes = "\\]\\[\\-\"\'"
private let swiftSymbols = "[" + ":{}(),.<_>/`?!@#$%&*+-^|=; \n" + quotes + "]"

private let regex = comments + "|" + words + "|" + swiftSymbols

class Protector {
    private typealias ProtectedClassHash = [String:String]
    private let files : [SwiftFile]
    
    init(files: [SwiftFile]) {
        self.files = files
    }
    
    func protect() {
        defer {
            exit(0)
        }
        let classHash = generateClassHash(from: files)
        guard classHash.isEmpty == false else {
            Logger.log("No class files to obfuscate.")
            return
        }
        protectClassReferences(hash: classHash)
        writeToFile(hash: classHash)
        return
    }
    
    private func generateClassHash(from files: [SwiftFile]) -> ProtectedClassHash {
        Logger.log("Scanning class declarations")
        guard files.isEmpty == false else {
            return [:]
        }
        var classes: ProtectedClassHash = [:]
        var scanData = SwiftFileScanData(phase: .reading)
        
        func regexMapClosure(fromData nsString: NSString) -> RegexClosure {
            return { result in
                scanData.currentWord = nsString.substring(with: result.rangeAt(0))
                defer {
                    scanData.prepareForNextWord()
                }
                guard scanData.shouldIgnoreCurrentWord == false else {
                    scanData.stopIgnoringWordsIfNeeded()
                    return nil
                }
                guard scanData.shouldProtectNextWord else {
                    scanData.protectNextWordIfNeeded()
                    scanData.startIgnoringWordsIfNeeded()
                    return nil
                }
                guard scanData.currentWord.isNotAnEmptyCharacter else {
                    return nil
                }
                scanData.shouldProtectNextWord = false
                guard scanData.wordSuccedingClassStringIsActuallyAClass else {
                    return nil
                }
                return scanData.currentWord
            }
        }
        
        for file in swiftFiles {
            Logger.log("--- Checking \(file.name) ---")
            do {
                let data = try String(contentsOfFile: file.path, encoding: .utf8)
                let newClasses = data.matchRegex(regex: regex, mappingClosure: regexMapClosure(fromData: data as NSString))
                newClasses.forEach {
                    let protectedClassName = String.random(length: protectedClassNameSize)
                    classes[$0] = protectedClassName
                    Logger.log("\($0) -> \(protectedClassName)", verbose: true)
                }
                scanData.prepareForNextFile()
            } catch {
                Logger.log("FATAL: \(error.localizedDescription)")
                exit(-1)
            }
        }
        return classes
    }
    
    private func protectClassReferences(hash: ProtectedClassHash) {
        Logger.log("--- Overwriting files ---")
        var scanData = SwiftFileScanData(phase: .overwriting)
        
        func regexMapClosure(fromData nsString: NSString) -> RegexClosure {
            return { result in
                scanData.currentWord = nsString.substring(with: result.rangeAt(0))
                defer {
                    scanData.prepareForNextWord()
                }
                guard scanData.shouldIgnoreCurrentWord == false else {
                    scanData.stopIgnoringWordsIfNeeded()
                    return nil
                }
                guard scanData.currentWordIsNotAParameterNameOrFramework, let protectedWord = hash[scanData.currentWord] else {
                    scanData.startIgnoringWordsIfNeeded()
                    return scanData.currentWord
                }
                return protectedWord
            }
        }
        for file in swiftFiles {
            let data = try! String(contentsOfFile: file.path, encoding: .utf8)
            let protectedClassData = data.matchRegex(regex: regex, mappingClosure: regexMapClosure(fromData: data as NSString)).joined()
            do {
                Logger.log("--- Overwriting \(file.name) ---")
                try protectedClassData.write(toFile: file.path, atomically: false, encoding: String.Encoding.utf8)
                scanData.prepareForNextFile()
            } catch {
                Logger.log("FATAL: \(error.localizedDescription)")
                exit(-1)
            }
        }
    }
    
    private func writeToFile(hash: ProtectedClassHash) {
        Logger.log("--- Generating conversion map ---")
        var output = ""
        output += "//\n"
        output += "//  SwiftShield\n"
        output += "//  Conversion Map\n"
        output += "//\n"
        output += "\n"
        output += "Classes:"
        output += "\n"
        for (k,v) in hash {
            output += "\n\(k) ===> \(v)"
        }
        let path = basePath + (basePath.characters.last == "/" ? "" : "/") + "swiftshield-output"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false, attributes: nil)
        do {
            try output.write(toFile: path + "/conversionMap.txt", atomically: false, encoding: String.Encoding.utf8)
        } catch {
            Logger.log("FATAL: Failed to generate conversion map: \(error.localizedDescription)")
        }
    }
    
}

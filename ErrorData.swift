//
//  ErrorData.swift
//  swiftshield
//
//  Created by Bruno Rocha on 2/8/17.
//  Copyright © 2017 Bruno Rocha. All rights reserved.
//

import Cocoa

struct ErrorData {
    let file: File
    let line: Int
    let column: Int
    let error: String
    let target: String
    let fullError: String
    
    init?(fullError: String) {
        let separated = fullError.components(separatedBy: ":")
        let file = File(filePath: separated[0])
        let line = Int(separated[1])!
        let column = Int(separated[2])!
        let separatedError = separated[4].components(separatedBy: "'")
        let specificError = separatedError[0].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let target = separatedError[1]
        
        self.file = file
        self.line = line
        self.error = specificError
        self.fullError = fullError
        
        switch error {
        case "cannot call value of non-function type":
            self.column = column - fullError.components(separatedBy: "module<")[1].components(separatedBy: ">")[0].characters.count
            self.target = fullError.components(separatedBy: "module<")[1].components(separatedBy: ">")[0]
        case "no such module", "could not build Objective-C module", "", "value of type", "cannot invoke initializer for type":
            return nil
        case "type": //type 'nrjCKwImewhNjhC' has no member 'ScaleMode'
            switch separatedError[2].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) {
            case "has no member":
                self.column = column + target.characters.count + 1
                self.target = separatedError[3]
            case "does not conform to protocol":
                return nil
            default:
                self.column = column
                self.target = target
            }
        default:
            self.column = column
            self.target = target
        }
    }
}

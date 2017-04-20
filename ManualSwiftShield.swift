//
//  ManualSwiftShield.swift
//  swiftshield
//
//  Created by Bruno Rocha on 4/20/17.
//  Copyright © 2017 Bruno Rocha. All rights reserved.
//

import Cocoa

struct ManualSwiftShield {
    func protect() {
        guard basePath.isEmpty == false else {
            Logger.log(String.badArguments)
            exit(error: true)
            return
        }
        let protector = Protector()
        let swiftFiles = getSwiftFiles()
        let tag = UserDefaults.standard.string(forKey: "tag") ?? "shielded"
        let obfuscationData = protector.findAndProtectReferencesManually(tag: tag, swiftFiles: swiftFiles)
        if obfuscationData.obfuscationDict.isEmpty {
            Logger.log("Found nothing to obfuscate. Finishing...")
            exit(error: true)
        }
        let projects = findFiles(rootPath: basePath, suffix: ".xcodeproj", ignoreDirs: false) ?? []
        protector.protectStoryboards(data: obfuscationData)
        protector.markAsProtected(projectPaths: projects)
        protector.writeToFile(data: obfuscationData)
        Logger.log("Finished.")
        exit()
    }
}

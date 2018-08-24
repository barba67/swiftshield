import Foundation

/// A Protector represents a system capable of obfuscating an iOS project.
class Protector {
    fileprivate let pbxProjRegex = ".*"
    fileprivate let pbxProjTargetNameRegex = "buildConfigurationList = (.*) \\/\\* .* PBXNativeTarget \"(.*)\""

    let basePath: String
    let protectedClassNameSize: Int

    init(basePath: String, protectedClassNameSize: Int = 25) {
        self.basePath = basePath
        self.protectedClassNameSize = protectedClassNameSize
        if basePath.isEmpty {
            Logger.log(.helpText)
            exit(error: true)
        }
    }

    func protect() -> ObfuscationData {
        return ObfuscationData()
    }

    func protectStoryboards(data obfuscationData: ObfuscationData) {
        Logger.log(.overwritingStoryboards)
        for file in obfuscationData.storyboardsToObfuscate {
            Logger.log(.checking(file: file))
            let data = try! Data(contentsOf: URL(fileURLWithPath: file.path))
            let xmlDoc = try! AEXMLDocument(xml: data, options: AEXMLOptions())
            obfuscateIBXML(element: xmlDoc.root, obfuscationData: obfuscationData)
            let obfuscatedFile = xmlDoc.xml
            Logger.log(.saving(file: file))
            do {
                try obfuscatedFile.write(toFile: file.path, atomically: true, encoding: .utf8)
            } catch {
                Logger.log(.fatal(error: error.localizedDescription))
                exit(error: true)
            }
        }
    }

    func obfuscateIBXML(element: AEXMLElement, currentModule: String? = nil, obfuscationData: ObfuscationData, idToXML: [String: AEXMLElement] = [:]) {
        var idToXML = idToXML
        let supportedModules = obfuscationData.moduleNames
        let currentModule: String = element.attributes["customModule"] ?? currentModule ?? ""
        if let identifier = element.attributes["id"] {
            idToXML[identifier] = element
        }
        if supportedModules?.contains(currentModule) != false {
            if let customClass = element.attributes["customClass"], let protectedClass = obfuscationData.obfuscationDict[customClass] {
                Logger.log(.protectedReference(originalName: customClass, protectedName: protectedClass))
                element.attributes["customClass"] = protectedClass
            }
        }
        if element.name == "action", let actionSelector = element.attributes["selector"], let trueName = actionSelector.components(separatedBy: ":").first, trueName.count > 4, let protectedClass = obfuscationData.obfuscationDict[trueName] {
            let actionModule = idToXML[element.attributes["destination"] ?? ""]?.attributes["customModule"] ?? ""
            if supportedModules?.contains(actionModule) != false {
                Logger.log(.protectedReference(originalName: trueName, protectedName: protectedClass))
                element.attributes["selector"] = protectedClass + ":"
            }
        }
        for child in element.children {
            obfuscateIBXML(element: child, currentModule: currentModule, obfuscationData: obfuscationData, idToXML: idToXML)
        }
    }

    func markProjectsAsProtected() {
        let projectPaths = findFiles(rootPath: basePath, suffix: ".xcodeproj", ignoreDirs: false) ?? []
        Logger.log(.taggingProjects)
        let targetLine = "PRODUCT_NAME ="
        let injectedLine = "SWIFTSHIELDED = true;"
        for projectPath in projectPaths {
            let path = projectPath+"/project.pbxproj"
            do {
                let data = try String(contentsOfFile: path, encoding: .utf8)
                var shouldInject = true
                let matches = data.match(regex: pbxProjRegex)
                let newProject = matches.compactMap { result in
                    let currentLine = (data as NSString).substring(with: result.range(at: 0))
                    guard shouldInject else {
                        return currentLine + "\n"
                    }
                    if currentLine.contains(injectedLine) {
                        shouldInject = false
                    } else if currentLine.contains(targetLine) {
                        return "\t\t" + injectedLine + "\n" + currentLine + "\n"
                    }
                    return currentLine + "\n"
                }.joined()
                try newProject.write(toFile: path, atomically: false, encoding: String.Encoding.utf8)
            } catch {
                Logger.log(.fatal(error: error.localizedDescription))
                exit(error: true)
            }
        }
    }

    func writeToFile(data: ObfuscationData) {
        Logger.log(.generatingConversionMap)
        var output = ""
        output += "//\n"
        output += "//  SwiftShield\n"
        output += "//  Conversion Map\n"
        output += "//\n"
        output += "\n"
        output += "Data:"
        output += "\n"
        for (k,v) in data.obfuscationDict {
            output += "\n\(k) ===> \(v)"
        }
        let path = basePath + (basePath.last == "/" ? "" : "/") + "swiftshield-output"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false, attributes: nil)
        do {
            try output.write(toFile: path + "/conversionMap.txt", atomically: false, encoding: String.Encoding.utf8)
        } catch {
            Logger.log(.fatal(error: error.localizedDescription))
        }
    }
}

extension Protector {
    func getStoryboardsAndXibs() -> [File] {
        return getFiles(suffix: ".storyboard") + getFiles(suffix: ".xib")
    }

    func getSourceFiles() -> [File] {
        return getSwiftFiles() + getFiles(suffix: ".h") + getFiles(suffix: ".m")
    }

    func getSwiftFiles() -> [File] {
        return getFiles(suffix: ".swift")
    }

    func getFiles(suffix: String) -> [File] {
        let filePaths = findFiles(rootPath: basePath, suffix: suffix) ?? []
        return filePaths.compactMap{ File(filePath: $0) }
    }

    func findFiles(rootPath: String, suffix: String, ignoreDirs: Bool = true) -> [String]? {
        var result = Array<String>()
        let fileManager = FileManager.default
        if let paths = fileManager.subpaths(atPath: rootPath) {
            let swiftPaths = paths.filter({ return $0.hasSuffix(suffix)})
            for path in swiftPaths {
                var isDir : ObjCBool = false
                let fullPath = (rootPath as NSString).appendingPathComponent(path)
                if fileManager.fileExists(atPath: fullPath, isDirectory: &isDir) {
                    if ignoreDirs == false || (ignoreDirs && isDir.boolValue == false) {
                        result.append(fullPath)
                    }
                }
            }
        }
        return result.count > 0 ? result : nil
    }
}

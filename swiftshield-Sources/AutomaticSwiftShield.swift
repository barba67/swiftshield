import Foundation

final class AutomaticSwiftShield: Protector {

    let projectToBuild: String
    let schemeToBuild: String

    var isWorkspace: Bool {
        return projectToBuild.hasSuffix(".xcworkspace")
    }

    init(basePath: String, projectToBuild: String = "", schemeToBuild: String = "") {
        self.projectToBuild = projectToBuild
        self.schemeToBuild = schemeToBuild
        super.init(basePath: basePath)
        if self.schemeToBuild.isEmpty || self.projectToBuild.isEmpty {
            Logger.log(.helpText)
            exit(error: true)
        }
    }

    override func protect() -> ObfuscationData {
        guard isWorkspace || projectToBuild.hasSuffix(".xcodeproj") else {
            Logger.log(.projectError)
            exit(error: true)
        }
        let modules = XcodeProjectBuilder(projectToBuild: projectToBuild, schemeToBuild: schemeToBuild).getModulesAndCompilerArguments()
        let obfuscationData = index(modules: modules)
        if obfuscationData.obfuscationDict.isEmpty {
            Logger.log(.foundNothingError)
            exit(error: true)
        }
        obfuscateReferences(obfuscationData: obfuscationData)
        return obfuscationData
    }
}

extension AutomaticSwiftShield {
    func index(modules: [Module]) -> ObfuscationData {
        let sourceKit = SourceKit()
        let obfuscationData = ObfuscationData()
        var fileDataArray: [(file: File, module: Module)] = []
        for module in modules {
            for file in module.files {
                fileDataArray.append((file, module))
            }
        }
        for fileData in fileDataArray {
            let file = fileData.file
            let module = fileData.module
            let compilerArgs = sourceKit.array(argv: module.compilerArguments)
            Logger.log(.indexing(file: file))
            let resp = index(sourceKit: sourceKit, file: file, args: compilerArgs)
            let dict = SKApi.sourcekitd_response_get_value(resp)
            sourceKit.recurseOver(childID: sourceKit.entitiesID, resp: dict) { [unowned self] dict in
                guard let data = self.getNameData(from: dict,
                                                  obfuscationData: obfuscationData,
                                                  sourceKit: sourceKit) else {
                                                    return
                }
                let name = data.name
                let usr = data.usr
                let obfuscatedName = data.obfuscatedName
                obfuscationData.usrDict.insert(usr)
                Logger.log(.foundDeclaration(name: name, usr: usr, newName: obfuscatedName))
            }
            obfuscationData.indexedFiles.append((file, resp))
        }
        return obfuscationData
    }

    private func index(sourceKit: SourceKit, file: File, args: sourcekitd_object_t) -> sourcekitd_response_t {
        let resp = sourceKit.indexFile(filePath: file.path, compilerArgs: args)
        if let error = sourceKit.error(resp: resp) {
            Logger.log(.indexError(file: file, error: error))
            exit(error: true)
        }
        return resp
    }

    private func getNameData(from dict: sourcekitd_variant_t, obfuscationData: ObfuscationData, sourceKit: SourceKit) -> (name: String, usr: String, obfuscatedName: String)? {
        let kind = dict.getUUIDString(key: sourceKit.kindID)
        guard let type = sourceKit.declarationType(for: kind) else {
            return nil
        }
        guard let name = dict.getString(key: sourceKit.nameID), let usr = dict.getString(key: sourceKit.usrID) else {
            return nil
        }
        guard let protected = obfuscationData.obfuscationDict[name] else {
            let newName = String.random(length: self.protectedClassNameSize)
            obfuscationData.obfuscationDict[name] = newName
            return (name, usr, newName)
        }
        return (name, usr, protected)
    }

    func obfuscateReferences(obfuscationData: ObfuscationData) {
        let SK = SourceKit()
        Logger.log(.searchingReferencesOfUsr)
        for (file,indexResponse) in obfuscationData.indexedFiles {
            let dict = SKApi.sourcekitd_response_get_value(indexResponse)
            SK.recurseOver( childID: SK.entitiesID, resp: dict, block: { dict in
                let kind = dict.getUUIDString(key: SK.kindID)
                guard SK.isReference(kind: kind) else {
                    return
                }
                guard let usr = dict.getString(key: SK.usrID), let name = dict.getString(key: SK.nameID) else {
                    return
                }
                let line = dict.getInt(key: SK.lineID)
                let column = dict.getInt(key: SK.colID)
                if obfuscationData.usrDict.contains(usr) {
                    Logger.log(.foundReference(name: name, usr: usr, at: file, line: line, column: column))
                    let reference = ReferenceData(name: name, line: line, column: column, file: file, usr: usr)
                    obfuscationData.add(reference: reference, toFile: file)
                }
            })
        }
        overwriteFiles(obfuscationData: obfuscationData)
    }

    func overwriteFiles(obfuscationData: ObfuscationData) {
        for (file,references) in obfuscationData.referencesDict {
            var sortedReferences = references.filterDuplicates { $0.line == $1.line && $0.column == $1.column }.sorted(by: lesserPosition)
            var line = 1
            var column = 1
            let data = try! String(contentsOfFile: file.path, encoding: .utf8)
            Logger.log(.overwriting(file: file))
            let matches = data.match(regex: String.swiftRegex)
            let obfuscatedFile = matches.flatMap { result in
                let word = (data as NSString).substring(with: result.rangeAt(0))
                var wordToReturn = word
                if sortedReferences.isEmpty == false && line == sortedReferences[0].line && column == sortedReferences[0].column {
                    sortedReferences.remove(at: 0)
                    wordToReturn = (obfuscationData.obfuscationDict[word] ?? word)
                }
                if word == "\n" {
                    line += 1
                    column = 1
                } else {
                    column += word.count
                }
                return wordToReturn
                }.joined()
            do {
                try obfuscatedFile.write(toFile: file.path, atomically: false, encoding: String.Encoding.utf8)
            } catch {
                Logger.log(.fatal(error: error.localizedDescription))
                exit(error: true)
            }
        }
    }
}

import Foundation

final class XcodeProjectBuilder {
    let projectToBuild: String
    let schemeToBuild: String
    let modulesToIgnore: Set<String>

    private typealias MutableModuleData = (source: [File], xibs: [File], plists: [File], args: [String])
    private typealias MutableModuleDictionary = OrderedDictionary<String, MutableModuleData>

    var isWorkspace: Bool {
        return projectToBuild.hasSuffix(".xcworkspace")
    }

    init(projectToBuild: String, schemeToBuild: String, modulesToIgnore: Set<String>) {
        self.projectToBuild = projectToBuild
        self.schemeToBuild = schemeToBuild
        self.modulesToIgnore = modulesToIgnore
    }

    func getModulesAndCompilerArguments() -> [Module] {
        if modulesToIgnore.isEmpty == false {
            Logger.log(.ignoreModules(modules: modulesToIgnore))
        }
        Logger.log(.buildingProject)
        let path = "/usr/bin/xcodebuild"
        let projectParameter = isWorkspace ? "-workspace" : "-project"
        let arguments: [String] = [projectParameter, projectToBuild, "-scheme", schemeToBuild]
        let cleanTask = Process()
        cleanTask.launchPath = path
        cleanTask.arguments = ["clean", "build"] + arguments + ["CODE_SIGN_IDENTITY=", "CODE_SIGNING_REQUIRED=NO"]
        let outpipe: Pipe = Pipe()
        cleanTask.standardOutput = outpipe
        cleanTask.standardError = outpipe
        cleanTask.launch()
        let outdata = outpipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: outdata, encoding: .utf8) else {
            Logger.log(.compilerArgumentsError)
            exit(error: true)
        }
        return parseModulesFrom(xcodeBuildOutput: output)
    }

    func parseModulesFrom(xcodeBuildOutput output: String) -> [Module] {
        let lines = output.components(separatedBy: "\n")
        var modules: MutableModuleDictionary = [:]
        for (index, line) in lines.enumerated() {
            if let moduleName = firstMatch(for: "(?<=-module-name ).*?(?= )", in: line) {
                parseMergeSwiftModulePhase(line: line, moduleName: moduleName, modules: &modules)
            } else if let moduleName = firstMatch(for: "(?<=--module ).*?(?= )", in: line) {
                parseCompileXibPhase(line: line, moduleName: moduleName, modules: &modules)
            } else if line.hasPrefix("ProcessInfoPlistFile") || line.hasPrefix("CopyPlistFile") {
                parsePlistPhase(line: line + lines[index + 1], modules: &modules)
            }
        }
        return modules.filter { modulesToIgnore.contains($0.key) == false }.map {
            Module(name: $0.key, sourceFiles: $0.value.source, xibFiles: $0.value.xibs, plists: $0.value.plists, compilerArguments: $0.value.args)
        }
    }

    private func parseMergeSwiftModulePhase(line: String, moduleName: String, modules: inout MutableModuleDictionary) {
        guard modules[moduleName]?.args.isEmpty != false else {
            return
        }
        guard let fullRelevantArguments = firstMatch(for: "/usr/bin/swiftc.*-module-name \(moduleName) .*", in: line) else {
            print("Fatal: Failed to retrieve \(moduleName) xcodebuild arguments")
            exit(error: true)
        }
        Logger.log(.found(module: moduleName))
        let relevantArguments = fullRelevantArguments.replacingEscapedSpaces
            .components(separatedBy: " ")
            .map { $0.removingPlaceholder }
        let files = parseModuleFiles(from: relevantArguments)
        let compilerArguments = parseCompilerArguments(from: relevantArguments)
        set(sourceFiles: files, to: moduleName, modules: &modules)
        set(compilerArgs: compilerArguments, to: moduleName, modules: &modules)
    }

    private func parseModuleFiles(from relevantArguments: [String]) -> [File] {
        var files: [File] = []
        var fileZone: Bool = false
        for arg in relevantArguments {
            if fileZone {
                if arg.hasPrefix("/") {
                    let file = File(filePath: arg)
                    files.append(file)
                }
                fileZone = arg.hasPrefix("-") == false || files.count == 0
            } else {
                fileZone = arg == "-c"
            }
        }
        return files
    }

    private func parseCompilerArguments(from relevantArguments: [String]) -> [String] {
        var args: [String?] = Array(relevantArguments.dropFirst())
        while let indexOfOutputMap = args.index(of: "-output-file-map") {
            args[indexOfOutputMap] = nil
            args[indexOfOutputMap + 1] = nil
        }
        let forbiddenArgs = ["-parseable-output", "-incremental", "-serialize-diagnostics", "-emit-dependencies"]
        for (index, arg) in args.enumerated() {
            if forbiddenArgs.contains(arg ?? "") {
                args[index] = nil
            } else if arg == "-O" {
                args[index] = "-Onone"
            } else if arg == "-DNDEBUG=1" {
                args[index] = "-DDEBUG=1"
            }
        }
        args.append(contentsOf: ["-D", "DEBUG"])
        return args.compactMap { $0 }
    }

    private func parseCompileXibPhase(line: String, moduleName: String, modules: inout MutableModuleDictionary) {
        let line = line.replacingEscapedSpaces
        guard let xibPath = firstMatch(for: "(?=)[^ ]*$", in: line) else {
            return
        }
        guard xibPath.hasSuffix(".xib") || xibPath.hasSuffix(".storyboard") else {
            return
        }
        let file = File(filePath: xibPath.removingPlaceholder)
        add(xib: file, to: moduleName, modules: &modules)
    }

    private func parsePlistPhase(line: String, modules: inout MutableModuleDictionary) {
        let line = line.replacingEscapedSpaces
        guard let regex = line.match(regex: "PlistFile (.*) (.*.plist) *cd (.*)").first else {
            print("Fatal: Plist row failed regex")
            exit(error: true)
        }
        let compiledPlistPath = regex.captureGroup(1, originalString: line)
        guard compiledPlistPath.hasSuffix(".plist") else {
            print("Fatal: Plist row has no .plist")
            exit(error: true)
        }
        let plistPath = regex.captureGroup(2, originalString: line)
        let folder = regex.captureGroup(3, originalString: line)
        let moduleNamePath = URL(fileURLWithPath: compiledPlistPath.removingPlaceholder)
                                .deletingLastPathComponent()
                                .lastPathComponent
        let moduleName: String
        if moduleNamePath.hasSuffix(".framework") {
            moduleName = String(moduleNamePath.prefix(moduleNamePath.count - 10))
        } else if moduleNamePath.hasSuffix(".app") {
            moduleName = String(moduleNamePath.prefix(moduleNamePath.count - 4))
        } else {
            print("Fatal: Unrecognized plist pattern")
            exit(error: true)
        }
        let file = File(filePath: folder.removingPlaceholder + "/" + plistPath.removingPlaceholder)
        add(plist: file, to: moduleName, modules: &modules)
    }
}

extension XcodeProjectBuilder {
    private func add(xib: File, to moduleName: String, modules: inout MutableModuleDictionary) {
        registerFoundModuleIfNeeded(moduleName, modules: &modules)
        modules[moduleName]?.xibs.append(xib)
    }

    private func set(sourceFiles: [File], to moduleName: String, modules: inout MutableModuleDictionary) {
        registerFoundModuleIfNeeded(moduleName, modules: &modules)
        modules[moduleName]?.source = sourceFiles
    }

    private func add(plist: File, to moduleName: String, modules: inout MutableModuleDictionary) {
        registerFoundModuleIfNeeded(moduleName, modules: &modules)
        modules[moduleName]?.plists.append(plist)
    }

    private func set(compilerArgs: [String], to moduleName: String, modules: inout MutableModuleDictionary) {
        registerFoundModuleIfNeeded(moduleName, modules: &modules)
        modules[moduleName]?.args = compilerArgs
    }

    private func registerFoundModuleIfNeeded(_ moduleName: String, modules: inout MutableModuleDictionary) {
        guard modules[moduleName] == nil else {
            return
        }
        let moduleData: MutableModuleData = ([], [], [], [])
        modules[moduleName] = moduleData
    }
}

import Foundation

final class ManualSwiftShield: Protector {
    let tag: String

    init(basePath: String, tag: String) {
        self.tag = tag
        super.init(basePath: basePath)
    }

    override func protect() -> ObfuscationData {
        let files = getSourceFiles()
        Logger.log(.scanningDeclarations)
        var obfsData = ObfuscationData()
        files.forEach { protect(file: $0, obfsData: &obfsData) }
        return obfsData
    }

    private func protect(file: File, obfsData: inout ObfuscationData) {
        Logger.log(.checking(file: file))
        do {
            let fileString = try String(contentsOfFile: file.path, encoding: .utf8)
            let newFile = obfuscateReferences(fileString: fileString, obfsData: &obfsData)
            try newFile.write(toFile: file.path, atomically: false, encoding: .utf8)
        } catch {
            Logger.log(.fatal(error: error.localizedDescription))
            exit(1)
        }
    }

    private func obfuscateReferences(fileString data: String, obfsData: inout ObfuscationData) -> String {
        var currentIndex = data.startIndex
        let matches = data.match(regex: String.regexFor(tag: tag))
        return matches.flatMap { result in
            let word = (data as NSString).substring(with: result.rangeAt(0))
            let protectedName: String = {
                guard let protected = obfsData.obfuscationDict[word] else {
                    let protected = String.random(length: protectedClassNameSize)
                    obfsData.obfuscationDict[word] = protected
                    return protected
                }
                return protected
            }()
            Logger.log(.protectedReference(originalName: word, protectedName: protectedName))
            let range: Range = currentIndex..<data.index(data.startIndex, offsetBy: result.range.location)
            currentIndex = data.index(range.upperBound, offsetBy: result.range.length)
            return data.substring(with: range) + protectedName
        }.joined() + (currentIndex < data.endIndex ? data.substring(with: currentIndex..<data.endIndex) : "")
    }
}

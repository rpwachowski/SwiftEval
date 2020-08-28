import Foundation
import BuildKit

public enum Evals {
    private static var counter: Int = 0
    
    private static func generateCount() -> Int {
        let ret = counter
        counter += 1
        return ret
    }
    
    private static func generateAnonymousName() -> String {
        let c = generateCount()
        return String(format: "SwiftEvalAnonymous%04d", c)
    }
    
    public static func eval(imports: [String] = [],
                            source: String) throws {
        let fn = try compileFunction0(imports: imports,
                                      returnType: Void.self,
                                      source: source)
        fn()
    }
    
    public static func compileFunction0<R>(
        imports: [String] = [],
        returnType: R.Type,
        source: String)
        throws -> () -> R
    {
        let name = generateAnonymousName()
        
        let imports = ["SwiftEval"] + imports
        
        let importLines = imports
            .map { "import \($0)" }
            .joined(separator: "\n")
        
        let d = String(repeating: " ", count: 4)
        let ____d = String(repeating: " ", count: 8)
        let ________d = String(repeating: " ", count: 12)
        
        let source = """
        \(importLines)

        public extension SwiftEvalPrivates {
        \(d)@_dynamicReplacement(for: function0)
        \(d)var __function_\(name): (() -> Any)? {
        \(____d)func fn() -> \(returnType) {
        \(________d)\(source.replacingOccurrences(of: "\n", with: "\n\(________d)"))
        \(____d)}
        \(____d)return fn
        \(d)}
        }
        """
        
        try compileAndLoad(name: name,
                           imports: imports,
                           source: source)
        guard let fn = SwiftEvalPrivates.shared.function0 else {
            throw MessageError("load function failed")
        }
        
        return { fn() as! R }
    }
    
    public static func compileFunction1<P1, R>(
        imports: [String] = [],
        parameter1Type: P1.Type,
        returnType: R.Type,
        source: String)
        throws -> (P1) -> R
    {
        let name = generateAnonymousName()

        let imports = ["SwiftEval"] + imports
        
        let importLines = imports
            .map { "import \($0)" }
            .joined(separator: "\n")
        
        let d = String(repeating: " ", count: 4)
        let ____d = String(repeating: " ", count: 8)
        let ________d = String(repeating: " ", count: 12)
        
        let source = """
        \(importLines)

        extension SwiftEvalPrivates {
        \(d)@_dynamicReplacement(for: function1)
        \(d)public var __function_\(name): ((Any) -> Any)? {
        \(____d)func fn(_ parameter1: \(parameter1Type)) -> \(returnType) {
        \(________d)\(source.replacingOccurrences(of: "\n", with: "\n\(________d)"))
        \(____d)}
        \(____d)return { (parameter1: Any) -> Any in
        \(________d)fn(parameter1 as! \(parameter1Type))
        \(____d)}
        \(d)}
        }
        """
        
        try compileAndLoad(name: name,
                           imports: imports,
                           source: source)
        
        guard let fn = SwiftEvalPrivates.shared.function1 else {
            throw MessageError("load function failed")
        }
        
        return { (parameter1: P1) -> R in
            fn(parameter1) as! R
        }
    }
    
    private static func compileAndLoad(
        name: String,
        imports: [String],
        source: String) throws
    {
        let env = try BuildEnvironments.detect()
        let tempDir = Utils.createTemporaryDirectory()
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try source.write(to: tempDir.appendingPathComponent("code.swift"),
                         atomically: true, encoding: .utf8)
        try fm.changeCurrentDirectory(at: tempDir)

        let linkingArguments: [String]
#if DEBUG
        // Allow copying frameworks to fail. If a dynamic library includes its own dependencies,
        // importing them will work but there will be no associated for those dependencies.
        let linkedFrameworks: [String] = imports.compactMap { module in
            let frameworkURL = env.packageFrameworksDirectory.appendingPathComponent("\(module).framework")
            let swiftmoduleURL = env.modulesDirectory.appendingPathComponent("\(module).swiftmodule")
            do {
                try fm.copyItem(atPath: frameworkURL.path, toPath: "\(fm.currentDirectoryPath)/\(module).framework")
                try fm.copyItem(atPath: swiftmoduleURL.path, toPath: "\(fm.currentDirectoryPath)/\(module).swiftmodule")
                return module
            } catch {
                print("[Info] module '\(module)' was missing either a framework or swiftmodule; will not explicitly link.")
                return nil
            }
        }
        linkingArguments = "-I . -L . -F .".args + Array(linkedFrameworks.map { ["-framework", "\($0)"] }.joined())
#else
        let linkedLibraries: [String] = imports.compactMap { module in
            let fileName = "lib\(module).dylib"
            let dylibURL = env.modulesDirectory.appendingPathComponent(fileName)
            do {
                try fm.copyItem(atPath: dylibURL.path, toPath: "\(fm.currentDirectoryPath)/\(fileName)")
                return module
            } catch {
                print("[Info] module '\(module)' was missing a dylib; will not explicitly link.")
                return nil
            }
        }

        try fm.contentsOfDirectory(atPath: env.modulesDirectory.path)
            .filter { $0.hasSuffix("swiftmodule") }
            .map(env.modulesDirectory.appendingPathComponent)
            .forEach {
                do {
                    try fm.copyItem(atPath: $0.path, toPath: "\(fm.currentDirectoryPath)/\($0.lastPathComponent)")
                } catch { print("[Warn] failed to copy swiftmodule at path \($0.path); compilation may fail.") }
            }
        linkingArguments = "-I . -L .".args + linkedLibraries.map { "lib\($0).dylib" }
#endif

        let args = "/usr/bin/swiftc -emit-library -module-name \(name) code.swift".args + linkingArguments
        let ret = Commands.run(args)
        guard ret.statusCode == EXIT_SUCCESS else { throw Commands.Error(ret.standardError) }
        let libPath = tempDir.appendingPathComponent("lib\(name).dylib")
        guard dlopen(libPath.path, RTLD_NOW) != nil else {
            throw MessageError("dlopen failed: \(libPath.path)")
        }
    }
}

private extension String {

    var args: [String] {
        split(separator: " ").map(String.init)
    }

}

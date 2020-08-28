import Foundation

public enum BuildEnvironments {
    public static func detect() throws -> BuildEnvironment {
        guard let execPath = Bundle.main.executableURL else {
            throw MessageError("no executableURL")
        }
        var dir = execPath.deletingLastPathComponent()
        while true {
            if dir.path == "/" {
                return CustomPathEnvironment(executablePath: execPath)
            }
            
            if dir.lastPathComponent == ".build" {
                return try SwiftPMEnvironment(executablePath: execPath)
            }
            
            if dir.lastPathComponent == "Products" {
                return try XcodeEnvironment(executablePath: execPath)
            }
            
            dir = dir.deletingLastPathComponent()
        }        
    }
}

public final class CustomPathEnvironment: BuildEnvironment {

    public let configuration: String
    private let executablePath: URL

    public var modulesDirectory: URL { executablePath.deletingLastPathComponent() }
    public var binaryDirectory: URL { executablePath.deletingLastPathComponent() }
    public var packageFrameworksDirectory: URL { executablePath.deletingLastPathComponent() }

    init(executablePath: URL) {
        configuration = "release"
        self.executablePath = executablePath
    }

}

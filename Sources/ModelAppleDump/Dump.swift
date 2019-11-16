import Foundation
import SwiftSoup

public struct Dump {

    static let models = [
        ModelInfo("macMinis", "https://support.apple.com/en-us/HT201894", "https://support.apple.com/specs/macmini", "Mac Mini"),
        ModelInfo("iMacs", "https://support.apple.com/en-us/HT201634", "https://support.apple.com/mac/imac", "iMac"),
        ModelInfo("macPros", "https://support.apple.com/en-us/HT202888", "https://support.apple.com/mac/mac-pro", "Mac Pro"),
        ModelInfo("macBooks", "https://support.apple.com/en-us/HT201608", "https://support.apple.com/mac/macbook", "Mac Book"),
        ModelInfo("macBookAirs", "https://support.apple.com/en-us/HT201862", "https://support.apple.com/mac/macbook-air", "Mac Book Air"),
        ModelInfo("macBookPros", "https://support.apple.com/en-us/HT201300", "https://support.apple.com/mac/macbook-pro", "Mac Book Pro")
    ]

    public static func renderer(for string: String) -> DevicesRenderer.Type {
        switch string {
        case "devicekit":
            return DeviceKitRenderer.self
        case "markdown":
            return MarkdownRenderer.self
        case "human", "emoji":
            return HumanRenderer.self
        default:
            return HumanRenderer.self
        }
    }
    public static func run(renderer rendererString: String) {
        let renderer = Dump.renderer(for: rendererString)

        for model in models {
            let (data, response, error) = URLSession.shared.synchronousDataTask(with: model.url)
            guard let dataUnwrapped = data, let html = String(data: dataUnwrapped, encoding: .utf8)  else {
                print("\(String(describing: error)), \(String(describing: response))")
                continue
            }
            var devices: [Device] = []
            do {
                let doc: Document = try SwiftSoup.parse(html)
                let links = try doc.select("a")
                for link in links {
                    let linkHref: String = try link.attr("href")
                    if linkHref.contains("https://support.apple.com/kb/SP") {
                        let modelName: String = try link.text()
                        guard !modelName.isEmpty else {
                            continue
                        }

                        if let paragraphe = link.parent(), let paragrapheWithImage = paragraphe.parent() {
                            var identifier = try paragraphe.text()
                            if let index = identifier.endIndex(of: "Model Identifier:") {
                                identifier = String(identifier[index...])
                            } else {
                                identifier = try paragrapheWithImage.text()
                                guard let upindex = identifier.endIndex(of: "Model Identifier:") else {

                                    continue
                                }
                                identifier = String(identifier[upindex...])
                            }
                            identifier = String(identifier.dropFirst())
                            identifier = String(identifier[identifier.startIndex..<identifier.index(of: " ")!])
                            identifier = String(identifier.replacingOccurrences(of: " ", with: ""))
                            let identifiers = identifier.split(separator: ";").map { String($0) }
                            //print("\(modelName): \(identifiers)")

                            let image = try paragrapheWithImage.select("img").first()!.attr("src")

                            let device = Device(
                                name: modelName.camelized,
                                kb: linkHref,
                                shortName: model.shortName,
                                identifier: identifiers,
                                image: image,
                                modelName: modelName)
                            if !device.identifier.isEmpty, !devices.contains(where: { return $0.name == device.name}) {
                                devices.append(device)
                            }
                        }
                    }
                }
            } catch Exception.Error(_, let message) {
                print(message)
            } catch {
                print("error")
            }

            renderer.render(devices: devices, model: model)
        }
    }
}

// MARK: - Models

public struct Device {
    var name: String
    var kb: String
    var shortName: String
    var identifier: [String]
    var image: String
    var modelName: String

    var toDeviveKit: String {
return """
            Device(
            "\(name)",
            "Device is a [\(modelName)](\(kb))",
            "https://support.apple.com\(image)",
            ["\(identifier.joined(separator: "\" ,\""))"], 0,(), "\(modelName)", -1, False, False, False, False, False, False, False, False, False, 0, False, 0)
"""
    }

    var toMarkdown: String {
        return """
        ### [\(modelName)](\(kb))
        * identifier: \(identifier.joined(separator: ","))
        ![\(name)](https://support.apple.com\(image))
        """
    }

    var toHuman: String {
return """
  🖥️ \(modelName)
  🔗 \(kb)
  🖼️ https://support.apple.com\(image)
  🆔 \(identifier.joined(separator: ", "))
"""
    }

}
public struct ModelInfo {
    var models: String
    var alternativeURL: String
    var urlString: String
    var shortName: String

    public init(_ models: String, _ urlString: String, _ alternativeURL: String, _  shortName: String) {
        self.models = models
        self.alternativeURL = alternativeURL
        self.urlString = urlString
        self.shortName = shortName
    }

    var url: URL {
        return URL(string: urlString)!
    }
}

public protocol DevicesRenderer {
    static func render(devices: [Device], model: ModelInfo)
}

public struct DeviceKitRenderer: DevicesRenderer {

    public static func render(devices: [Device], model: ModelInfo) {
        print("## \(model.alternativeURL), \(model.urlString)")
        print("\(model.models) = [")
        print(devices.map { $0.toDeviveKit }.joined(separator: ",\n"))
        print("]")
    }

}

public struct MarkdownRenderer: DevicesRenderer {

    public static func render(devices: [Device], model: ModelInfo) {
        print("## [\(model.shortName)](\(model.alternativeURL))")
        print("\n")
        print(devices.map { $0.toMarkdown }.joined(separator: "\n"))
    }

}

public struct HumanRenderer: DevicesRenderer {

    public static func render(devices: [Device], model: ModelInfo) {
        print("🖥️ \(model.shortName)")
        print("🔗 \(model.alternativeURL)")
        print("")
        print(devices.map { $0.toHuman}.joined(separator: "\n\n"))
        print("")
    }

}

// MARK: - Extensions

extension URLSession {
    func synchronousDataTask(with url: URL) -> (Data?, URLResponse?, Error?) {
        var data: Data?
        var response: URLResponse?
        var error: Error?

        let semaphore = DispatchSemaphore(value: 0)

        let dataTask = self.dataTask(with: url) {
            data = $0
            response = $1
            error = $2

            semaphore.signal()
        }
        dataTask.resume()

        _ = semaphore.wait(timeout: .distantFuture)

        return (data, response, error)
    }
}
extension StringProtocol {
    func index<S: StringProtocol>(of string: S, options: String.CompareOptions = []) -> Index? {
        range(of: string, options: options)?.lowerBound
    }
    func endIndex<S: StringProtocol>(of string: S, options: String.CompareOptions = []) -> Index? {
        range(of: string, options: options)?.upperBound
    }
    func indices<S: StringProtocol>(of string: S, options: String.CompareOptions = []) -> [Index] {
        var indices: [Index] = []
        var startIndex = self.startIndex
        while startIndex < endIndex,
            let range = self[startIndex...]
                .range(of: string, options: options) {
                    indices.append(range.lowerBound)
                    startIndex = range.lowerBound < range.upperBound ? range.upperBound :
                        index(range.lowerBound, offsetBy: 1, limitedBy: endIndex) ?? endIndex
        }
        return indices
    }
    func ranges<S: StringProtocol>(of string: S, options: String.CompareOptions = []) -> [Range<Index>] {
        var result: [Range<Index>] = []
        var startIndex = self.startIndex
        while startIndex < endIndex,
            let range = self[startIndex...]
                .range(of: string, options: options) {
                    result.append(range)
                    startIndex = range.lowerBound < range.upperBound ? range.upperBound :
                        index(range.lowerBound, offsetBy: 1, limitedBy: endIndex) ?? endIndex
        }
        return result
    }
}
private let badChars = CharacterSet.alphanumerics.inverted

extension String {
    var uppercasingFirst: String {
        return prefix(1).uppercased() + dropFirst()
    }

    var lowercasingFirst: String {
        return prefix(1).lowercased() + dropFirst()
    }

    var camelized: String {
        guard !isEmpty else {
            return ""
        }

        let parts = self.components(separatedBy: badChars)

        let first = String(describing: parts.first!).lowercasingFirst
        let rest = parts.dropFirst().map({String($0).uppercasingFirst})

        return ([first] + rest).joined(separator: "")
    }
}
import Foundation
import UIKit

enum IPAIconReplacementError: LocalizedError {
    case invalidImage
    case invalidBundle
    case invalidPlist
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "替换图标不是有效图片"
        case .invalidBundle: return "应用目录不存在"
        case .invalidPlist: return "无法读取或修改 Info.plist"
        case .encodingFailed: return "无法生成图标 PNG"
        }
    }
}

/// Works in the temporary unpacked Payload/*.app directory, before Zsign.
enum IPAIconReplacement {
    static func apply(png: Data, to app: URL) throws {
        guard let input = UIImage(data: png), input.size.width > 0, input.size.height > 0 else {
            throw IPAIconReplacementError.invalidImage
        }
        let plistURL = app.appendingPathComponent("Info.plist")
        guard var plist = NSDictionary(contentsOf: plistURL) as? [String: Any] else {
            throw IPAIconReplacementError.invalidPlist
        }
        var rendered = [(String, Data)]()
        for (name, width) in [
            ("ZNIcon60x60@2x.png", 120),
            ("ZNIcon60x60@3x.png", 180),
            ("ZNIcon76x76@2x~ipad.png", 152),
            ("ZNIcon83.5x83.5@2x~ipad.png", 167)
        ] {
            let size = CGSize(width: width, height: width)
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { context in
                UIColor.clear.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                // Center crop for square icons without stretching source imagery.
                let ratio = max(size.width / input.size.width, size.height / input.size.height)
                let scaled = CGSize(width: input.size.width * ratio, height: input.size.height * ratio)
                input.draw(in: CGRect(x: (size.width - scaled.width) / 2,
                                     y: (size.height - scaled.height) / 2,
                                     width: scaled.width, height: scaled.height))
            }
            guard let data = image.pngData() else { throw IPAIconReplacementError.encodingFailed }
            rendered.append((name, data))
        }
        // Build all outputs before mutating the bundle. The original source IPA is never modified.
        for (name, bytes) in rendered {
            try bytes.write(to: app.appendingPathComponent(name), options: .atomic)
        }
        plist["CFBundleIcons"] = [
            "CFBundlePrimaryIcon": [
                "CFBundleIconFiles": ["ZNIcon60x60@2x", "ZNIcon60x60@3x"]
            ]
        ]
        plist["CFBundleIcons~ipad"] = [
            "CFBundlePrimaryIcon": [
                "CFBundleIconFiles": ["ZNIcon60x60@2x", "ZNIcon76x76@2x~ipad", "ZNIcon83.5x83.5@2x~ipad"]
            ]
        ]
        plist["CFBundleIconFile"] = "ZNIcon60x60@2x"
        guard (plist as NSDictionary).write(to: plistURL, atomically: true) else {
            throw IPAIconReplacementError.invalidPlist
        }
        guard let verify = NSDictionary(contentsOf: plistURL) as? [String: Any],
              let icons = verify["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              files.contains("ZNIcon60x60@3x"),
              FileManager.default.fileExists(atPath: app.appendingPathComponent("ZNIcon60x60@3x.png").path)
        else { throw IPAIconReplacementError.invalidPlist }
    }
}

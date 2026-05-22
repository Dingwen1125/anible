import AppKit
import UniformTypeIdentifiers

enum PetState {
    case idle
    case walking
    case jumping
    case falling
    case held
    case sleeping

    static func weightedRandom() -> PetState {
        let roll = Int.random(in: 0..<100)
        switch roll {
        case 0..<42:
            return .idle
        case 42..<66:
            return .walking
        case 66..<88:
            return .jumping
        default:
            return .sleeping
        }
    }
}

private extension PetState {
    var portraitPose: PetPortraitPose {
        switch self {
        case .idle:
            return .idle
        case .walking:
            return .walking
        case .jumping:
            return .jumping
        case .falling:
            return .falling
        case .held:
            return .held
        case .sleeping:
            return .sleeping
        }
    }
}

enum PetPortraitPose: String, CaseIterable {
    case idle
    case walking
    case jumping
    case falling
    case held
    case sleeping

    var displayName: String {
        switch self {
        case .idle:
            return "不动"
        case .walking:
            return "行走"
        case .jumping:
            return "跳跃"
        case .falling:
            return "掉落"
        case .held:
            return "悬空/被抓起"
        case .sleeping:
            return "睡觉"
        }
    }

    var recommendedFrameCount: Int {
        switch self {
        case .idle:
            return 1
        case .walking:
            return 4
        case .jumping:
            return 3
        case .falling:
            return 2
        case .held:
            return 2
        case .sleeping:
            return 2
        }
    }

    var fileNamePrefix: String {
        rawValue
    }

    var notes: String {
        switch self {
        case .idle:
            return "站立或趴着的普通待机图。"
        case .walking:
            return "一组循环走路帧，建议脚步有左右变化。"
        case .jumping:
            return "起跳、空中、落地三帧。"
        case .falling:
            return "从空中掉下来的姿态。"
        case .held:
            return "被鼠标抓起来时的悬空姿态。"
        case .sleeping:
            return "闭眼睡觉，可以带蜷缩姿态。"
        }
    }
}

struct PetPortraitUploadRequirement {
    let pose: PetPortraitPose
    let requiredFrameCount: Int
    let acceptedFileExtensions: [String]
    let recommendedSize: NSSize
    let notes: String

    var exampleFileNames: [String] {
        (1...requiredFrameCount).map {
            "\(pose.fileNamePrefix)_\(String(format: "%02d", $0)).png"
        }
    }
}

enum PetPortraitUploadInterface {
    static let acceptedFileExtensions = ["png", "webp"]
    static let recommendedSize = NSSize(width: 296, height: 264)

    static var requirements: [PetPortraitUploadRequirement] {
        PetPortraitPose.allCases.map {
            PetPortraitUploadRequirement(
                pose: $0,
                requiredFrameCount: $0.recommendedFrameCount,
                acceptedFileExtensions: acceptedFileExtensions,
                recommendedSize: recommendedSize,
                notes: $0.notes
            )
        }
    }

    static var totalRequiredFrameCount: Int {
        requirements.reduce(0) { $0 + $1.requiredFrameCount }
    }

    static func requirementsText() -> String {
        let header = """

        Pet portrait upload requirements:
        - Format: transparent PNG or WebP
        - Recommended size: \(Int(recommendedSize.width))x\(Int(recommendedSize.height))
        - Required total: \(totalRequiredFrameCount) images
        """

        let lines = requirements.map { requirement in
            let examples = requirement.exampleFileNames.joined(separator: ", ")
            return "- \(requirement.pose.displayName): \(requirement.requiredFrameCount) image(s). Examples: \(examples). \(requirement.notes)"
        }

        return ([header] + lines).joined(separator: "\n")
    }

    static func missingRequirements(from uploadedFileNames: [String]) -> [PetPortraitUploadRequirement] {
        requirements.filter { requirement in
            let matchingCount = uploadedFileNames.filter { fileName in
                let lowercased = fileName.lowercased()
                return lowercased.hasPrefix("\(requirement.pose.fileNamePrefix)_")
                    && acceptedFileExtensions.contains(where: { lowercased.hasSuffix(".\($0)") })
            }.count
            return matchingCount < requirement.requiredFrameCount
        }
    }
}

enum PetPortraitUploadWizard {
    static func run() throws -> PetPortraitSet {
        var framesByPose: [PetPortraitPose: [NSImage]] = [:]

        for requirement in PetPortraitUploadInterface.requirements {
            let images = try chooseImages(for: requirement)
            framesByPose[requirement.pose] = images
        }

        return PetPortraitSet(framesByPose: framesByPose)
    }

    private static func chooseImages(for requirement: PetPortraitUploadRequirement) throws -> [NSImage] {
        while true {
            let intro = NSAlert()
            intro.messageText = "上传：\(requirement.pose.displayName)"
            intro.informativeText = """
            现在需要上传 \(requirement.requiredFrameCount) 张「\(requirement.pose.displayName)」图片。

            \(requirement.notes)

            接下来会一张一张选择。系统会自动把这些图片归类为「\(requirement.pose.displayName)」，不需要你按文件名命名。
            """
            intro.addButton(withTitle: "开始选择")
            intro.addButton(withTitle: "取消并使用默认宠物")

            guard intro.runModal() == .alertFirstButtonReturn else {
                throw NSError(
                    domain: "AniblePetPortraits",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "你取消了「\(requirement.pose.displayName)」图片上传。"]
                )
            }

            do {
                return try (1...requirement.requiredFrameCount).map { frameNumber in
                    try chooseSingleImage(for: requirement, frameNumber: frameNumber)
                }
            } catch {
                let retry = NSAlert()
                retry.alertStyle = .warning
                retry.messageText = "图片选择未完成"
                retry.informativeText = "\(error.localizedDescription)\n\n要重新选择「\(requirement.pose.displayName)」这一组吗？"
                retry.addButton(withTitle: "重新选择")
                retry.addButton(withTitle: "使用默认宠物")
                if retry.runModal() == .alertFirstButtonReturn {
                    continue
                }
                throw error
            }
        }
    }

    private static func chooseSingleImage(for requirement: PetPortraitUploadRequirement, frameNumber: Int) throws -> NSImage {
        let panel = NSOpenPanel()
        panel.message = "请选择「\(requirement.pose.displayName)」第 \(frameNumber) / \(requirement.requiredFrameCount) 张图片"
        panel.prompt = "上传这一张"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = PetPortraitUploadInterface.acceptedFileExtensions.compactMap {
            UTType(filenameExtension: $0)
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            throw NSError(
                domain: "AniblePetPortraits",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "你取消了第 \(frameNumber) 张「\(requirement.pose.displayName)」图片选择。"]
            )
        }

        guard let image = NSImage(contentsOf: url) else {
            throw NSError(
                domain: "AniblePetPortraits",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "第 \(frameNumber) 张「\(requirement.pose.displayName)」图片无法读取。"]
            )
        }

        return image
    }
}

final class PetPortraitSet {
    private let framesByPose: [PetPortraitPose: [NSImage]]

    init(framesByPose: [PetPortraitPose: [NSImage]]) {
        self.framesByPose = framesByPose
    }

    init(folderURL: URL) throws {
        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let fileNames = fileURLs.map(\.lastPathComponent)
        let missing = PetPortraitUploadInterface.missingRequirements(from: fileNames)
        guard missing.isEmpty else {
            let missingText = missing
                .map { "\($0.pose.displayName): 需要 \($0.requiredFrameCount) 张，例如 \($0.exampleFileNames.joined(separator: ", "))" }
                .joined(separator: "\n")
            throw NSError(
                domain: "AniblePetPortraits",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "缺少这些画像：\n\(missingText)"]
            )
        }

        var loadedFrames: [PetPortraitPose: [NSImage]] = [:]
        for requirement in PetPortraitUploadInterface.requirements {
            let urls = fileURLs
                .filter { url in
                    let lowercased = url.lastPathComponent.lowercased()
                    return lowercased.hasPrefix("\(requirement.pose.fileNamePrefix)_")
                        && PetPortraitUploadInterface.acceptedFileExtensions.contains { lowercased.hasSuffix(".\($0)") }
                }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .prefix(requirement.requiredFrameCount)

            let images = urls.compactMap { NSImage(contentsOf: $0) }
            guard images.count == requirement.requiredFrameCount else {
                throw NSError(
                    domain: "AniblePetPortraits",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "\(requirement.pose.displayName) 有图片无法读取。"]
                )
            }
            loadedFrames[requirement.pose] = images
        }

        framesByPose = loadedFrames
    }

    func image(for state: PetState) -> NSImage? {
        guard let frames = framesByPose[state.portraitPose], !frames.isEmpty else { return nil }
        let frameIndex = Int(Date().timeIntervalSinceReferenceDate * 6) % frames.count
        return frames[frameIndex]
    }

    func frames(for pose: PetPortraitPose) -> [NSImage] {
        framesByPose[pose] ?? []
    }
}

enum PetProfileStore {
    private struct StoredProfile: Codable {
        let id: String
        let name: String
    }

    private static var supportDirectory: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("LocalPets", isDirectory: true)
    }

    private static var petsDirectory: URL {
        supportDirectory.appendingPathComponent("Pets", isDirectory: true)
    }

    private static var manifestURL: URL {
        supportDirectory.appendingPathComponent("profiles.json")
    }

    static func loadProfiles() -> [PetProfile] {
        var profiles: [PetProfile] = [.defaultPet]
        guard
            let data = try? Data(contentsOf: manifestURL),
            let storedProfiles = try? JSONDecoder().decode([StoredProfile].self, from: data)
        else {
            return profiles
        }

        for storedProfile in storedProfiles {
            let folderURL = petsDirectory.appendingPathComponent(storedProfile.id, isDirectory: true)
            guard let portraitSet = try? PetPortraitSet(folderURL: folderURL) else { continue }
            profiles.append(PetProfile(id: storedProfile.id, name: storedProfile.name, portraitSet: portraitSet))
        }

        return profiles
    }

    static func saveNewProfile(name: String, portraitSet: PetPortraitSet) throws -> PetProfile {
        try FileManager.default.createDirectory(at: petsDirectory, withIntermediateDirectories: true)

        let id = UUID().uuidString
        let folderURL = petsDirectory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        for requirement in PetPortraitUploadInterface.requirements {
            let frames = portraitSet.frames(for: requirement.pose)
            for (index, image) in frames.enumerated() {
                let fileName = "\(requirement.pose.fileNamePrefix)_\(String(format: "%02d", index + 1)).png"
                let fileURL = folderURL.appendingPathComponent(fileName)
                try savePNG(image, to: fileURL)
            }
        }

        var storedProfiles = loadStoredProfiles()
        storedProfiles.append(StoredProfile(id: id, name: name))
        try saveStoredProfiles(storedProfiles)

        return PetProfile(id: id, name: name, portraitSet: portraitSet)
    }

    static func deleteProfile(_ profile: PetProfile) throws {
        guard !profile.isDefault else { return }
        let folderURL = petsDirectory.appendingPathComponent(profile.id, isDirectory: true)
        if FileManager.default.fileExists(atPath: folderURL.path) {
            try FileManager.default.removeItem(at: folderURL)
        }

        let storedProfiles = loadStoredProfiles().filter { $0.id != profile.id }
        try saveStoredProfiles(storedProfiles)
    }

    private static func loadStoredProfiles() -> [StoredProfile] {
        guard
            let data = try? Data(contentsOf: manifestURL),
            let profiles = try? JSONDecoder().decode([StoredProfile].self, from: data)
        else {
            return []
        }
        return profiles
    }

    private static func saveStoredProfiles(_ profiles: [StoredProfile]) throws {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(profiles)
        try data.write(to: manifestURL, options: .atomic)
    }

    private static func savePNG(_ image: NSImage, to url: URL) throws {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw NSError(
                domain: "AniblePetPortraits",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "无法保存图片 \(url.lastPathComponent)。"]
            )
        }

        try pngData.write(to: url, options: .atomic)
    }
}

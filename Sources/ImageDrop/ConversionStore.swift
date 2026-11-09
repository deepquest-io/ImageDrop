// ImageDrop by deepquest | https://deepquest.code511.com/blog
import Foundation
import AppKit
import UniformTypeIdentifiers

enum JobStatus: Equatable {
    case queued
    case working
    case done
    case failed(String)
}

struct Job: Identifiable {
    let id = UUID()
    let source: URL
    let originalBytes: Int64
    var status: JobStatus = .queued
    var output: URL?
    var outputBytes: Int64 = 0
    var width = 0
    var height = 0
    var note: String?
    var thumbnail: NSImage?
}

@MainActor
final class ConversionStore: ObservableObject {
    static let shared = ConversionStore()

    static let sizeOptions = [0, 4096, 3840, 2560, 2048, 1920, 1600, 1280, 1024, 800, 640]

    @Published private(set) var jobs: [Job] = []

    @Published var format: OutputFormat { didSet { defaults.set(format.rawValue, forKey: Keys.format) } }
    @Published var quality: Double { didSet { defaults.set(quality, forKey: Keys.quality) } }
    @Published var webpMode: WebPMode { didSet { defaults.set(webpMode.rawValue, forKey: Keys.webpMode) } }
    @Published var maxDimension: Int { didSet { defaults.set(maxDimension, forKey: Keys.maxDimension) } }
    @Published var keepMetadata: Bool { didSet { defaults.set(keepMetadata, forKey: Keys.keepMetadata) } }
    @Published var outputFolder: URL? { didSet { defaults.set(outputFolder?.path, forKey: Keys.outputFolder) } }

    private let defaults = UserDefaults.standard
    private var running = 0
    private var reservedOutputs = Set<String>()
    private let maxConcurrent = max(2, min(6, ProcessInfo.processInfo.activeProcessorCount / 2))

    private enum Keys {
        static let format = "format", quality = "quality", webpMode = "webpMode"
        static let maxDimension = "maxDimension", keepMetadata = "keepMetadata", outputFolder = "outputFolder"
    }

    private init() {
        let d = UserDefaults.standard
        let savedFormat = OutputFormat(rawValue: d.string(forKey: Keys.format) ?? "") ?? .webp
        format = OutputFormat.available.contains(savedFormat) ? savedFormat : .webp
        quality = d.object(forKey: Keys.quality) as? Double ?? 80
        webpMode = WebPMode(rawValue: d.string(forKey: Keys.webpMode) ?? "") ?? .smart
        maxDimension = d.object(forKey: Keys.maxDimension) as? Int ?? 0
        keepMetadata = d.bool(forKey: Keys.keepMetadata)
        if let path = d.string(forKey: Keys.outputFolder),
           FileManager.default.fileExists(atPath: path) {
            outputFolder = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            outputFolder = nil
        }
    }

    // MARK: - Derived state

    var qualityApplies: Bool {
        format.usesQuality && !(format == .webp && webpMode == .lossless)
    }

    var isWorking: Bool { running > 0 }

    var summary: String {
        guard !jobs.isEmpty else { return "No images yet" }
        let done = jobs.filter { $0.status == .done }
        let failed = jobs.filter { if case .failed = $0.status { return true } else { return false } }.count
        let before = done.reduce(Int64(0)) { $0 + $1.originalBytes }
        let after = done.reduce(Int64(0)) { $0 + $1.outputBytes }
        var text = "\(done.count) of \(jobs.count) converted"
        if before > 0 {
            let saved = before - after
            let pct = Int((Double(saved) / Double(before) * 100).rounded())
            text += saved >= 0
                ? " · saved \(Self.bytes(saved)) (\(pct)%)"
                : " · \(Self.bytes(-saved)) larger"
        }
        if failed > 0 { text += " · \(failed) failed" }
        return text
    }

    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    // MARK: - Adding files

    func add(_ urls: [URL]) {
        let inFlight = Set(jobs.filter { $0.status == .queued || $0.status == .working }.map { $0.source.standardizedFileURL })
        var seen = inFlight
        for file in urls.flatMap(expand) {
            let key = file.standardizedFileURL
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            jobs.append(Job(source: file, originalBytes: Self.fileSize(file)))
        }
        pump()
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.image, .folder]
        panel.prompt = "Convert"
        if panel.runModal() == .OK { add(panel.urls) }
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Save Here"
        if panel.runModal() == .OK, let url = panel.url { outputFolder = url }
    }

    func clearFinished() {
        jobs.removeAll { $0.status != .working && $0.status != .queued }
    }

    func revealOutputs() {
        let urls = jobs.compactMap { $0.status == .done ? $0.output : nil }
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    /// Files are taken as-is (ImageIO decides if they're readable); folders are
    /// scanned recursively for image files.
    private func expand(_ url: URL) -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return [] }
        guard isDir.boolValue else { return [url] }

        guard let walker = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .contentTypeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }

        var found: [URL] = []
        for case let file as URL in walker {
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey])
            if values?.isRegularFile == true, values?.contentType?.conforms(to: .image) == true {
                found.append(file)
            }
        }
        return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return Int64(size)
    }

    // MARK: - Processing queue

    private var currentSettings: ConversionSettings {
        ConversionSettings(format: format, quality: quality, webpMode: webpMode,
                           maxDimension: maxDimension, keepMetadata: keepMetadata)
    }

    private func pump() {
        while running < maxConcurrent, let index = jobs.firstIndex(where: { $0.status == .queued }) {
            jobs[index].status = .working
            let jobID = jobs[index].id
            let source = jobs[index].source
            let settings = currentSettings
            let output = reserveOutputURL(for: source, format: settings.format)
            running += 1

            Task.detached(priority: .userInitiated) {
                let result = Result { try Converter.convert(source: source, to: output, settings: settings) }
                await MainActor.run {
                    ConversionStore.shared.finish(jobID: jobID, output: output, result: result)
                }
            }
        }
        objectWillChange.send()
    }

    private func finish(jobID: UUID, output: URL, result: Result<ConversionResult, Error>) {
        running -= 1
        reservedOutputs.remove(output.standardizedFileURL.path)

        if let index = jobs.firstIndex(where: { $0.id == jobID }) {
            switch result {
            case .success(let r):
                jobs[index].status = .done
                jobs[index].output = r.output
                jobs[index].outputBytes = r.bytes
                jobs[index].width = r.width
                jobs[index].height = r.height
                jobs[index].note = r.note
                if let cg = r.thumbnail { jobs[index].thumbnail = NSImage(cgImage: cg, size: .zero) }
            case .failure(let error):
                jobs[index].status = .failed(error.localizedDescription)
            }
        }
        pump()
    }

    /// Never overwrites: photo.png → photo.webp, or photo-1.webp if that exists.
    private func reserveOutputURL(for source: URL, format: OutputFormat) -> URL {
        let folder = outputFolder ?? source.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent
        let sourcePath = source.standardizedFileURL.path
        var n = 0
        while true {
            let name = n == 0 ? "\(base).\(format.fileExtension)" : "\(base)-\(n).\(format.fileExtension)"
            let candidate = folder.appendingPathComponent(name)
            let path = candidate.standardizedFileURL.path
            if path != sourcePath,
               !reservedOutputs.contains(path),
               !FileManager.default.fileExists(atPath: path) {
                reservedOutputs.insert(path)
                return candidate
            }
            n += 1
        }
    }
}

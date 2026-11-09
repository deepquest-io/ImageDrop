// ImageDrop by deepquest | https://deepquest.code511.com/blog
import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var store: ConversionStore
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            SettingsPanel(store: store)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            ZStack {
                if store.jobs.isEmpty {
                    DropPrompt(isTargeted: isTargeted) { store.chooseFiles() }
                        .padding(20)
                } else {
                    JobList(store: store)
                    if isTargeted {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentColor.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                            )
                            .padding(8)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter { $0.isFileURL }
                store.add(files)
                return !files.isEmpty
            } isTargeted: { targeted in
                isTargeted = targeted
            }

            Divider()

            FooterBar(store: store)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
    }
}

// MARK: - Settings

private struct SettingsPanel: View {
    @ObservedObject var store: ConversionStore

    private var metadataHelp: String {
        store.format == .webp
            ? "WebP output is always stripped of metadata for the smallest size."
            : "Copy EXIF, GPS and IPTC data to the converted file."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Picker("Convert to", selection: $store.format) {
                    ForEach(OutputFormat.available) { format in
                        Text(format.label).tag(format)
                    }
                }
                .fixedSize()

                if store.format == .webp {
                    Picker("WebP mode", selection: $store.webpMode) {
                        ForEach(WebPMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .help(store.webpMode.help)
                }

                Spacer()

                Picker("Max size", selection: $store.maxDimension) {
                    ForEach(ConversionStore.sizeOptions, id: \.self) { size in
                        Text(verbatim: size == 0 ? "Original" : "\(size) px").tag(size)
                    }
                }
                .fixedSize()
                .help("Longest side. Images are only ever scaled down, never up.")
            }

            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Text("Quality")
                    Slider(value: $store.quality, in: 1...100, step: 1)
                        .frame(minWidth: 140, maxWidth: 220)
                    Text("\(Int(store.quality))")
                        .monospacedDigit()
                        .frame(width: 28, alignment: .trailing)
                }
                .disabled(!store.qualityApplies)
                .opacity(store.qualityApplies ? 1 : 0.45)
                .help("80 is a great default for WebP: visually near-identical, much smaller.")

                Toggle("Keep metadata", isOn: $store.keepMetadata)
                    .disabled(store.format == .webp)
                    .help(metadataHelp)

                Spacer()

                HStack(spacing: 6) {
                    Text("Save to")
                    Menu {
                        Button("Same folder as original") { store.outputFolder = nil }
                        Divider()
                        Button("Choose Folder…") { store.chooseOutputFolder() }
                    } label: {
                        Label(store.outputFolder?.lastPathComponent ?? "Same folder", systemImage: "folder")
                    }
                    .fixedSize()
                }
            }
        }
    }
}

// MARK: - Empty state

private struct DropPrompt: View {
    let isTargeted: Bool
    let browse: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
            Text("Drop images or folders here")
                .font(.title2.weight(.semibold))
            Text("JPEG · PNG · HEIC · WebP · AVIF · TIFF · GIF · BMP · RAW and more")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Choose Files…", action: browse)
                .controlSize(.large)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isTargeted ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                              style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
        )
        .animation(.easeOut(duration: 0.15), value: isTargeted)
    }
}

// MARK: - Job list

private struct JobList: View {
    @ObservedObject var store: ConversionStore

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.jobs) { job in
                    JobRow(job: job)
                    Divider().padding(.leading, 68)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct JobRow: View {
    let job: Job

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(job.output?.lastPathComponent ?? job.source.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(isFailed ? Color.red : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            status

            if job.status == .done, let output = job.output {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([output])
                } label: {
                    Image(systemName: "magnifyingglass.circle")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .help(job.source.path)
    }

    @ViewBuilder private var thumbnail: some View {
        if let image = job.thumbnail {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Image(nsImage: NSWorkspace.shared.icon(forFile: job.source.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }

    @ViewBuilder private var status: some View {
        switch job.status {
        case .queued:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .working:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private var isFailed: Bool {
        if case .failed = job.status { return true }
        return false
    }

    private var subtitle: String {
        let original = ConversionStore.bytes(job.originalBytes)
        switch job.status {
        case .queued:
            return "Waiting · \(original)"
        case .working:
            return "Converting · \(original)"
        case .failed(let message):
            return message
        case .done:
            var parts = ["\(original) → \(ConversionStore.bytes(job.outputBytes))"]
            if job.originalBytes > 0 {
                let change = (Double(job.outputBytes) - Double(job.originalBytes)) / Double(job.originalBytes) * 100
                parts[0] += String(format: " (%@%.0f%%)", change < 0 ? "−" : "+", abs(change))
            }
            parts.append("\(job.width)×\(job.height)")
            if let note = job.note { parts.append(note) }
            return parts.joined(separator: " · ")
        }
    }
}

// MARK: - Footer

private struct FooterBar: View {
    @ObservedObject var store: ConversionStore

    var body: some View {
        HStack(spacing: 10) {
            if store.isWorking {
                ProgressView().controlSize(.small)
            }
            Text(store.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Link("by \(Credits.author)", destination: Credits.url)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(Credits.url.absoluteString)
            Button("Show in Finder") { store.revealOutputs() }
                .disabled(!store.jobs.contains { $0.status == .done })
            Button("Clear") { store.clearFinished() }
                .disabled(store.jobs.isEmpty)
            Button("Add Files…") { store.chooseFiles() }
                .keyboardShortcut(.defaultAction)
        }
    }
}

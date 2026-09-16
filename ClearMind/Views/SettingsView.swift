import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let clearMindBackup = UTType(exportedAs: "com.local.clearmind.backup", conformingTo: .json)
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.clearMindBackup, .json] }
    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var exportDocument = BackupDocument()
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var pendingImportData: Data?
    @State private var pendingImportSummary = ""
    @State private var message: SettingsMessage?

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            PageHeader("设置")

            VStack(alignment: .leading, spacing: 12) {
                SectionHeading("本地备份")
                QuietDivider()
                HStack(spacing: 12) {
                    Button("导出备份…") { prepareExport() }
                        .buttonStyle(PrimaryButtonStyle())
                    Button("导入备份…") { showingImporter = true }
                        .buttonStyle(QuietButtonStyle())
                    Spacer()
                }
                Text("导入会替换当前内容。执行前，应用会在本地自动保留一份安全快照。")
                    .font(.system(size: 12))
                    .foregroundStyle(CMTheme.textSecondary)
                    .lineSpacing(3)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("隐私")
                    .font(.system(size: 15, weight: .semibold))
                Text("Clear Mind 不包含账号、网络同步、分析统计或遥测。除非你主动选择备份位置，应用不会访问其他文件。")
                    .font(.system(size: 12))
                    .foregroundStyle(CMTheme.textSecondary)
                    .lineSpacing(4)
            }

            Spacer()
        }
        .padding(32)
        .background(CMTheme.canvas)
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .clearMindBackup,
            defaultFilename: "Clear Mind Backup"
        ) { result in
            if case .failure(let error) = result {
                message = SettingsMessage(title: "导出失败", details: error.localizedDescription)
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.clearMindBackup, .json]) { result in
            handleImportSelection(result)
        }
        .confirmationDialog(
            "用备份替换当前内容？",
            isPresented: Binding(
                get: { pendingImportData != nil },
                set: { if !$0 { pendingImportData = nil } }
            )
        ) {
            Button("导入并替换", role: .destructive) { performImport() }
            Button("取消", role: .cancel) { pendingImportData = nil }
        } message: {
            Text("备份包含：\(pendingImportSummary)。当前数据会先自动保存一份安全快照。")
        }
        .alert(item: $message) { message in
            Alert(title: Text(message.title), message: Text(message.details), dismissButton: .default(Text("好")))
        }
    }

    private func prepareExport() {
        do {
            exportDocument = BackupDocument(data: try BackupService.exportData(from: modelContext))
            showingExporter = true
        } catch {
            message = SettingsMessage(title: "导出失败", details: error.localizedDescription)
        }
    }

    private func handleImportSelection(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            pendingImportSummary = try BackupService.summary(of: data)
            pendingImportData = data
        } catch {
            message = SettingsMessage(title: "无法读取备份", details: error.localizedDescription)
        }
    }

    private func performImport() {
        guard let data = pendingImportData else { return }
        do {
            try BackupService.importData(data, into: modelContext)
            pendingImportData = nil
            message = SettingsMessage(title: "导入完成", details: "备份内容已恢复到本地数据库。")
        } catch {
            pendingImportData = nil
            message = SettingsMessage(title: "导入失败", details: error.localizedDescription)
        }
    }
}

private struct SettingsMessage: Identifiable {
    let id = UUID()
    let title: String
    let details: String
}

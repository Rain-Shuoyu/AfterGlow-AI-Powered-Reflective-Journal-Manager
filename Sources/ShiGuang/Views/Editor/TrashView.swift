import SwiftUI

/// Sheet showing the soft-deleted diary entries. Lets the user restore
/// them back to the active diary folder, or permanently delete them.
/// Opened from the trash icon in the writing tab's header.
struct TrashView: View {
    @ObservedObject var trash: DiaryTrash
    /// Folder to restore into. If nil, the restore button is disabled.
    let restoreFolder: URL?
    let onClose: () -> Void

    @State private var showEmptyConfirm: Bool = false
    @State private var restoreError: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            content
        }
        .frame(idealWidth: 580, idealHeight: 480)
        .background {
            ZStack {
                LiquidBackdrop().ignoresSafeArea()
            }
        }
        .alert("清空回收站？", isPresented: $showEmptyConfirm) {
            Button("取消", role: .cancel) {}
            Button("永久删除", role: .destructive) { trash.emptyTrash() }
        } message: {
            Text("回收站里所有文件将被永久删除，操作不可撤销。")
        }
        .alert("恢复失败", isPresented: .constant(restoreError != nil)) {
            Button("好") { restoreError = nil }
        } message: {
            Text(restoreError ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                onClose()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("返回")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
                Text("回收站")
                    .font(.callout.weight(.medium))
                Text("· \(trash.entries.count) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !trash.entries.isEmpty {
                Button {
                    showEmptyConfirm = true
                } label: {
                    Text("清空")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("永久删除回收站里所有文件")
            }
        }
        .padding(.horizontal, DS.Spacing.l)
        .padding(.top, DS.Spacing.m)
        .padding(.bottom, DS.Spacing.s)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if trash.entries.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.s) {
            Image(systemName: "trash.slash")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("回收站是空的")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            ForEach(trash.entries) { entry in
                row(for: entry)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(for entry: TrashedEntry) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.displayName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(entry.trashedAt.formatted(date: .abbreviated, time: .shortened))
                    Text("·")
                    Text(formatBytes(entry.fileSize))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                guard let folder = restoreFolder else { return }
                if !trash.restore(entry, to: folder) {
                    restoreError = "恢复失败：可能是目标目录不可写"
                }
            } label: {
                Label("恢复", systemImage: "arrow.uturn.left")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .disabled(restoreFolder == nil)
            .help(restoreFolder == nil ? "请先选择日记目录" : "恢复到当前日记目录")

            Button(role: .destructive) {
                trash.permanentlyDelete(entry)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .help("永久删除这条")
        }
        .padding(.vertical, 4)
    }

    private func formatBytes(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB]
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }
}

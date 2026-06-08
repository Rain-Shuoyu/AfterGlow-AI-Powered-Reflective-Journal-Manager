import SwiftUI

/// Full-screen markdown editor. Owns its own `EditorState` (draft) and is
/// dismissed via `onClose`. Save is gated by `state.isDirty`; closing with
/// unsaved changes pops a confirmation.
///
/// The body is a `LiveMarkdownEditor` — an NSTextView-backed view that
/// styles markdown in real time as the user types. The user never sees
/// the raw `##` / `**` / `` ` `` markers; they're rendered with
/// `foregroundColor: .clear` so the cursor moves through them normally
/// while the body is styled with the right font/size/weight/background.
struct EditorView: View {
    @EnvironmentObject var store: DiaryStore
    @State var state: EditorState
    let onClose: () -> Void

    @State private var showUnsavedConfirm: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var lastError: String? = nil
    @State private var justSaved: Bool = false
    @State private var backHovered: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, DS.Spacing.l)
                .padding(.top, DS.Spacing.m)
                .padding(.bottom, DS.Spacing.s)

            Divider().opacity(0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.l) {
                    EditorHeaderCard(state: $state)
                        .onChange(of: state.date) { _, _ in state.isDirty = true }
                        .onChange(of: state.title) { _, _ in state.isDirty = true }
                        .onChange(of: state.mood) { _, _ in state.isDirty = true }
                        .onChange(of: state.moodLabel) { _, _ in state.isDirty = true }
                        .onChange(of: state.weather) { _, _ in state.isDirty = true }
                        .onChange(of: state.tags) { _, _ in state.isDirty = true }

                    bodySection
                }
                .padding(DS.Spacing.l)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background {
            ZStack {
                LiquidBackdrop().ignoresSafeArea()
            }
        }
        .alert("未保存的修改", isPresented: $showUnsavedConfirm) {
            Button("放弃修改", role: .destructive) { onClose() }
            Button("继续编辑", role: .cancel) {}
        } message: {
            Text("你有未保存的修改，确定要放弃吗？")
        }
        .alert("删除日记？", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { deleteCurrent() }
        } message: {
            Text("将永久删除该 Markdown 文件，操作不可撤销。")
        }
        .alert("保存失败", isPresented: .constant(lastError != nil)) {
            Button("好") { lastError = nil }
        } message: {
            Text(lastError ?? "")
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: DS.Spacing.s) {
            // Back button — explicit hit area (32pt tall) and hover
            // ring so the click target is comfortable on a trackpad.
            // The plain chevron+text was easy to miss at the top
            // corner of the sheet.
            Button {
                attemptClose()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("返回")
                }
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    Capsule(style: .continuous)
                        .fill(.regularMaterial)
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            backHovered ? DS.Brand.amber.opacity(0.55) : .clear,
                            lineWidth: 1
                        )
                }
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .keyboardShortcut(.escape, modifiers: [])
            .onHover { backHovered = $0 }
            .help("返回  (⎋)")

            Spacer()

            // Mode indicator — the body is always "live", but the title
            // and a small icon remind the user that the markdown is being
            // styled as they type.
            HStack(spacing: 4) {
                Image(systemName: "wand.and.stars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Live Markdown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                Capsule().fill(.white.opacity(0.05))
            }

            if state.isDirty {
                Text("未保存")
                    .font(.caption)
                    .foregroundStyle(DS.Brand.amber)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background {
                        Capsule().fill(DS.Brand.amber.opacity(0.15))
                    }
                    .transition(.opacity.combined(with: .scale))
            }

            // Delete button — only for existing entries (new entries have
            // no file to delete). `Cmd+Delete` is the standard Mac
            // shortcut; both the toolbar button and the shortcut open
            // the same confirmation alert.
            if state.editingURL != nil {
                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .help("删除这条日记  (⌘⌫)")
                .keyboardShortcut(.delete, modifiers: .command)
            }

            if justSaved {
                Text("已保存")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background {
                        Capsule().fill(.green.opacity(0.15))
                    }
                    .transition(.opacity.combined(with: .scale))
            }

            Button {
                save()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                    Text("保存")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(DS.Brand.amber)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!state.isDirty && state.editingURL != nil)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: state.isDirty)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: justSaved)
    }

    // MARK: - Body

    private var bodySection: some View {
        LiveMarkdownEditor(text: $state.body)
            .frame(minHeight: 420)
            // No card background, no border. The text view is just a text
            // view — anything wrapping it (material, stroke, etc.) reads
            // as a "rectangle matching the background color" the user can
            // see scrolling under the cursor.
            .onChange(of: state.body) { _, _ in
                if !state.isDirty { state.isDirty = true }
            }
    }

    // MARK: - Actions

    private func save() {
        if let _ = store.save(state) {
            state.isDirty = false
            justSaved = true
            // Hide the "已保存" pill after a moment.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                justSaved = false
            }
        } else {
            lastError = store.lastError ?? "未知错误"
        }
    }

    private func attemptClose() {
        if state.isDirty {
            showUnsavedConfirm = true
        } else {
            onClose()
        }
    }

    private func deleteCurrent() {
        guard let url = state.editingURL,
              let entry = store.entries.first(where: { $0.url == url }) else { return }
        // Routed through the store so the file lands in the recycle bin
        // and the entry list auto-refreshes.
        store.delete(entry: entry)
        // Force a clean close (no unsaved-confirm dialog).
        state.isDirty = false
        onClose()
    }
}

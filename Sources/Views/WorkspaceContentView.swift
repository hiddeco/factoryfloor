// ABOUTME: Workspace tab bar, tab list, and tab content for a single workstream.
// ABOUTME: Extracted from TerminalContainerView to keep the orchestration shell lean.

import os
import SwiftUI

/// Identity and directory context shared across workspace content views.
struct WorkspaceContext {
    let workstreamID: UUID
    let workingDirectory: String
    let projectDirectory: String
    let projectName: String
    let workstreamName: String
}

/// Parent-provided orchestration state that WorkspaceContentView renders but does not own.
struct WorkspaceSessionState {
    let claudeCommand: String?
    let claudeID: UUID
    let sessionMode: TerminalSessionMode
    let scriptConfig: ScriptConfig
    let browserDefaultURL: String
    let branchPR: GitHubPR?
    let envVars: [String: String]
    let terminalEnvVars: [String: String]
    let setupGateCommand: String?
}

// MARK: - Editor & file-tree coordinator

/// Reference-type coordinator owning editor bridge, dirty state, file tree,
/// and directory watcher. Stored as `@StateObject` in WorkspaceContentView
/// so that closures capture a stable reference instead of a struct copy.
@MainActor
final class EditorCoordinator: ObservableObject {
    @Published var editorDirtyState: [UUID: Bool] = [:]
    @Published var fileTree: [FileNode] = []
    @Published var gitFileStatuses = GitFileStatusProvider()
    @Published private(set) var editorBridge: MonacoEditorBridge?

    private var directoryWatcher: DirectoryWatcher?
    private var refreshGeneration = 0
    private var refreshDebounceTask: Task<Void, Never>?
    private let workingDirectory: String

    init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    // MARK: - Editor bridge

    func createEditorBridgeIfNeeded() {
        guard editorBridge == nil else { return }
        let bridge = MonacoEditorBridge()
        bridge.onContentChanged = { [weak self] modelId, dirty in
            guard let self else { return }
            if let uuid = UUID(uuidString: modelId) {
                self.editorDirtyState[uuid] = dirty
            }
        }
        editorBridge = bridge
    }

    // MARK: - File tree watcher

    func startFileTreeWatcherIfNeeded() {
        guard directoryWatcher == nil else { return }
        refreshFileTree()
        directoryWatcher = DirectoryWatcher(path: workingDirectory) { [weak self] in
            self?.debounceRefreshFileTree()
        }
    }

    func stopWatcherIfUnneeded(hasEditorTabs: Bool) {
        if !hasEditorTabs {
            refreshGeneration += 1
            directoryWatcher?.stop()
            directoryWatcher = nil
            fileTree = []
            gitFileStatuses = GitFileStatusProvider()
        }
    }

    func refreshFileTree() {
        refreshGeneration += 1
        let gen = refreshGeneration
        let currentTree = fileTree
        let root = workingDirectory
        DispatchQueue.global(qos: .userInitiated).async {
            let tree: [FileNode]
            if currentTree.isEmpty {
                tree = FileNode.buildShallowTree(rootPath: root)
            } else {
                tree = FileNode.refreshLoadedNodes(in: currentTree, rootPath: root)
            }
            let statuses = GitOperations.fileStatuses(at: root)
            DispatchQueue.main.async { [weak self] in
                guard let self, gen == self.refreshGeneration else { return }
                self.fileTree = tree
                self.gitFileStatuses = GitFileStatusProvider(fileStatuses: statuses)
            }
        }
    }

    func expandFolder(_ relativePath: String) {
        if let node = FileNode.findNode(atPath: relativePath, in: fileTree), node.isLoaded { return }
        let gen = refreshGeneration
        let root = workingDirectory
        DispatchQueue.global(qos: .userInitiated).async {
            let children = FileNode.loadChildren(atRelativePath: relativePath, rootPath: root)
            DispatchQueue.main.async { [weak self] in
                guard let self, gen == self.refreshGeneration else { return }
                self.fileTree = FileNode.insertChildren(children, atPath: relativePath, in: self.fileTree)
            }
        }
    }

    private func debounceRefreshFileTree() {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            refreshFileTree()
        }
    }
}

// MARK: - WorkspaceContentView

struct WorkspaceContentView: View {
    let context: WorkspaceContext
    let isActive: Bool
    let workspaceStarted: Bool
    let state: WorkspaceSessionState
    @Binding var setupGateState: SetupGateState
    @Binding var runStoppedManually: Bool
    @Binding var runStarted: Bool
    let onContinueAfterSetup: () -> Void

    @EnvironmentObject var surfaceCache: TerminalSurfaceCache
    @EnvironmentObject var appEnv: AppEnvironment
    @AppStorage("factoryfloor.editorTabActive") private var editorTabActive: Bool = false
    @AppStorage("factoryfloor.editorFileDirty") private var editorFileDirty: Bool = false

    @State private var activeTab: WorkspaceTab
    @State private var tabs: [WorkspaceTab]
    @State private var terminalCount: Int
    @State private var browserCount: Int
    @State private var editorCount: Int
    @State private var draggedCustomTab: WorkspaceTab?
    @State private var browserTitles: [UUID: String]
    @State private var terminalTitles: [UUID: String]
    @State private var editorFilePaths: [UUID: String]
    @StateObject private var coordinator: EditorCoordinator

    init(
        context: WorkspaceContext,
        isActive: Bool,
        workspaceStarted: Bool,
        state: WorkspaceSessionState,
        setupGateState: Binding<SetupGateState>,
        runStoppedManually: Binding<Bool>,
        runStarted: Binding<Bool>,
        onContinueAfterSetup: @escaping () -> Void,
        initialTabState: WorkspaceTabSnapshot
    ) {
        self.context = context
        self.isActive = isActive
        self.workspaceStarted = workspaceStarted
        self.state = state
        self._setupGateState = setupGateState
        self._runStoppedManually = runStoppedManually
        self._runStarted = runStarted
        self.onContinueAfterSetup = onContinueAfterSetup
        _coordinator = StateObject(wrappedValue:
            EditorCoordinator(workingDirectory: context.workingDirectory))
        _activeTab = State(initialValue: initialTabState.activeTab)
        _tabs = State(initialValue: initialTabState.tabs)
        _terminalCount = State(initialValue: initialTabState.terminalCount)
        _browserCount = State(initialValue: initialTabState.browserCount)
        _editorCount = State(initialValue: initialTabState.editorCount)
        _browserTitles = State(initialValue: initialTabState.browserTitles)
        _terminalTitles = State(initialValue: initialTabState.terminalTitles)
        _editorFilePaths = State(initialValue: initialTabState.editorFilePaths)
    }

    // MARK: - Computed properties

    private var setupGateID: UUID {
        derivedUUID(from: context.workstreamID, salt: "setup-gate")
    }

    /// Surface IDs that should be rendering for the active tab.
    private var visibleSurfaceIDs: Set<UUID>? {
        switch activeTab {
        case .agent:
            if setupGateState == .running || setupGateState == .failed {
                return [setupGateID]
            }
            return [state.claudeID]
        case let .terminal(id): return [id]
        case .info, .browser, .editor: return []
        }
    }

    private var isEditorTabActive: Bool {
        if case .editor = activeTab { return true }
        return false
    }

    private var isActiveEditorDirty: Bool {
        if case let .editor(id) = activeTab { return coordinator.editorDirtyState[id] == true }
        return false
    }

    private var fixedTabs: [WorkspaceTab] {
        tabs.filter { !$0.isCloseable }
    }

    private var closeableTabs: [WorkspaceTab] {
        tabs.filter(\.isCloseable)
    }

    private static let compactTabThreshold = 3

    private var useCompactTabs: Bool {
        tabs.filter(\.isCloseable).count > Self.compactTabThreshold
    }

    // MARK: - Setup gate overlay

    private var setupGateRunningView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Running setup...")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.bar)
            Divider()
            SingleTerminalView(
                surfaceID: setupGateID,
                workingDirectory: context.workingDirectory,
                command: state.setupGateCommand ?? "",
                isFocused: true,
                environmentVars: state.terminalEnvVars
            )
        }
    }

    private var setupGateFailedView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 11))
                Text("Setup failed.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Continue to Agent") {
                    onContinueAfterSetup()
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.bar)
            Divider()
            SingleTerminalView(
                surfaceID: setupGateID,
                workingDirectory: context.workingDirectory,
                command: state.setupGateCommand ?? "",
                isFocused: false,
                environmentVars: state.terminalEnvVars
            )
        }
    }

    // MARK: - Body

    var body: some View {
        paneContent
            .onReceive(NotificationCenter.default.publisher(for: .switchByNumber)) { notification in
                guard isActive else { return }
                guard let n = notification.object as? Int, n >= 1 else { return }
                guard n <= tabs.count else { return }
                activeTab = tabs[n - 1]
            }
            .onReceive(NotificationCenter.default.publisher(for: .nextTab)) { _ in
                guard isActive else { return }
                guard let currentIndex = tabs.firstIndex(of: activeTab) else { return }
                activeTab = tabs[(currentIndex + 1) % tabs.count]
            }
            .onReceive(NotificationCenter.default.publisher(for: .prevTab)) { _ in
                guard isActive else { return }
                guard let currentIndex = tabs.firstIndex(of: activeTab) else { return }
                activeTab = tabs[(currentIndex - 1 + tabs.count) % tabs.count]
            }
            .onReceive(NotificationCenter.default.publisher(for: .terminalTabExited)) { notification in
                guard let surfaceID = notification.object as? UUID else { return }
                if let tab = tabs.first(where: {
                    if case let .terminal(id) = $0 { return id == surfaceID }
                    return false
                }) {
                    closeTab(tab)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .browserTitleChanged)) { notification in
                guard let tabID = notification.object as? UUID else { return }
                browserTitles[tabID] = notification.userInfo?["title"] as? String
            }
            .onReceive(NotificationCenter.default.publisher(for: .terminalTitleChanged)) { notification in
                guard let surfaceID = notification.object as? UUID else { return }
                terminalTitles[surfaceID] = notification.userInfo?["title"] as? String
            }
    }

    private var paneContent: some View {
        paneLayout
            .onChange(of: activeTab) {
                guard isActive else { return }
                editorTabActive = isEditorTabActive
                editorFileDirty = isActiveEditorDirty
                surfaceCache.updateOcclusion(visibleSurfaceIDs: visibleSurfaceIDs)
                WorkspaceStateStore.save(RestorableWorkspaceTab(activeTab: activeTab), for: context.workstreamID)
                appEnv.refreshWorktreeState(for: context.workingDirectory, projectDirectory: context.projectDirectory)
            }
            .onChange(of: isActive) { _, active in
                editorTabActive = active && isEditorTabActive
                editorFileDirty = active && isActiveEditorDirty
                if active {
                    surfaceCache.updateOcclusion(visibleSurfaceIDs: visibleSurfaceIDs)
                } else {
                    saveTabSnapshot()
                }
            }
            .onChange(of: setupGateState) {
                guard isActive else { return }
                surfaceCache.updateOcclusion(visibleSurfaceIDs: visibleSurfaceIDs)
            }
            .onChange(of: coordinator.editorDirtyState) {
                if case let .editor(id) = activeTab {
                    editorFileDirty = coordinator.editorDirtyState[id] == true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleInfo)) { _ in
                guard isActive else { return }
                activeTab = .info
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusAgent)) { _ in
                guard isActive else { return }
                activeTab = .agent
            }
            .onReceive(NotificationCenter.default.publisher(for: .rerunScript)) { _ in
                guard isActive else { return }
                activeTab = .info
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleTerminal)) { _ in
                guard isActive else { return }
                addTerminal()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleBrowser)) { _ in
                guard isActive else { return }
                addBrowser()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleEditor)) { _ in
                guard isActive else { return }
                openEditor()
            }
            .onReceive(NotificationCenter.default.publisher(for: .closeTerminal)) { _ in
                guard isActive else { return }
                if activeTab.isCloseable { closeTab(activeTab) }
            }
    }

    private var paneLayout: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            tabContent
        }
        .onAppear {
            if isActive {
                editorTabActive = isEditorTabActive
                editorFileDirty = isActiveEditorDirty
                surfaceCache.updateOcclusion(visibleSurfaceIDs: visibleSurfaceIDs)
            }
            if tabs.contains(where: { if case .editor = $0 { return true } else { return false } }) {
                coordinator.startFileTreeWatcherIfNeeded()
            }
            // Eagerly create the Monaco bridge so it's ready when the user
            // opens an editor tab. The WKWebView is created lazily inside
            // ensureWebView() (needs a real container to avoid 0×0 init).
            coordinator.createEditorBridgeIfNeeded()
        }
        .onDisappear {
            if isActive {
                editorTabActive = false
                editorFileDirty = false
            }
            guard workspaceStarted else { return }
            saveTabSnapshot()
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(fixedTabs, id: \.self) { tab in
                tabButton(for: tab)
            }

            if !closeableTabs.isEmpty {
                ScrollableTabStrip(
                    tabs: closeableTabs,
                    activeTab: activeTab,
                    tabButton: { tab in tabButton(for: tab) }
                )
                .layoutPriority(-1)
            }

            Spacer()

            HStack(spacing: 2) {
                TabBarActionButton(icon: "terminal", shortcut: "\u{2318}T", tooltip: "New Terminal (\u{2318}T)", action: addTerminal)
                TabBarActionButton(icon: "globe", shortcut: "\u{2318}B", tooltip: "New Browser (\u{2318}B)", action: addBrowser)
                TabBarActionButton(icon: "doc.text", shortcut: "\u{2318}O", tooltip: "New Editor (\u{2318}O)", action: openEditor)
            }
            .fixedSize()

            if let pr = state.branchPR, let url = URL(string: pr.url) {
                let prColor: Color = pr.state == "MERGED" ? .purple : .green
                Button(action: { NSWorkspace.shared.open(url) }) {
                    HStack(spacing: 4) {
                        Image(systemName: pr.state == "MERGED" ? "arrow.triangle.merge" : "arrow.triangle.pull")
                            .font(.system(size: 11))
                        Text(verbatim: "#\(pr.number)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(prColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(prColor)
                }
                .buttonStyle(.borderless)
                .help(pr.title)
                .accessibilityLabel(Text(verbatim: "Pull request #\(pr.number)"))
                .accessibilityHint(pr.title)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .info:
            WorkstreamInfoView(
                workstreamID: context.workstreamID,
                workstreamName: context.workstreamName,
                workingDirectory: context.workingDirectory,
                projectName: context.projectName,
                projectDirectory: context.projectDirectory,
                scriptConfig: state.scriptConfig,
                environmentVars: state.terminalEnvVars,
                runStoppedManually: $runStoppedManually,
                runStarted: $runStarted,
                sessionMode: state.sessionMode
            )
        case .agent:
            if setupGateState == .running {
                setupGateRunningView
            } else if setupGateState == .failed {
                setupGateFailedView
            } else if state.sessionMode == .waitingForTools || appEnv.isDetecting {
                terminalLoadingView(message: "Checking terminal tools...")
            } else if appEnv.toolStatus.claude.path == nil {
                VStack(spacing: 16) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("Claude Code not found")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Install Claude Code to use the Coding Agent.")
                        .foregroundStyle(.tertiary)
                    Link("Install Claude Code", destination: URL(string: "https://docs.anthropic.com/en/docs/claude-code/overview")!)
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let claudeCommand = state.claudeCommand {
                SingleTerminalView(
                    surfaceID: state.claudeID,
                    workingDirectory: context.workingDirectory,
                    command: claudeCommand,
                    isFocused: true,
                    environmentVars: state.envVars
                )
            } else {
                terminalLoadingView(message: "Preparing Coding Agent...")
            }
        case let .terminal(id):
            SingleTerminalView(
                surfaceID: id,
                workingDirectory: context.workingDirectory,
                isFocused: true,
                environmentVars: state.terminalEnvVars
            )
        case let .browser(id):
            BrowserView(defaultURL: state.browserDefaultURL, tabID: id, webView: surfaceCache.webView(for: id))
                .id(id)
        case let .editor(id):
            if let bridge = coordinator.editorBridge {
                EditorView(
                    workingDirectory: context.workingDirectory,
                    fileTree: coordinator.fileTree,
                    gitStatus: coordinator.gitFileStatuses,
                    initialFilePath: editorFilePaths[id],
                    bridge: bridge,
                    modelId: id.uuidString,
                    isDirtyState: Binding(
                        get: { coordinator.editorDirtyState[id] ?? false },
                        set: { coordinator.editorDirtyState[id] = $0 }
                    ),
                    onFileChanged: { path in
                        if let path {
                            editorFilePaths[id] = path
                        } else {
                            editorFilePaths.removeValue(forKey: id)
                        }
                        saveTabSnapshot()
                    },
                    onExpandFolder: { path in
                        coordinator.expandFolder(path)
                    }
                )
                .id(id)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Tab button

    @ViewBuilder
    private func tabButton(for tab: WorkspaceTab) -> some View {
        let shortcut = tabShortcut(tab) ?? closeableTabShortcut(tab)
        let button = WorkspaceTabButton(
            tab: tab,
            label: tabLabel(tab),
            icon: tabIcon(tab),
            shortcut: shortcut,
            isActive: activeTab == tab,
            isDirty: isEditorDirty(tab),
            onSelect: { activeTab = tab },
            onClose: tab.isCloseable ? { closeTab(tab) } : nil
        )

        if tab.isCloseable {
            button
                .onDrag {
                    draggedCustomTab = tab
                    return NSItemProvider(object: NSString(string: tabDragIdentifier(tab)))
                }
                .onDrop(of: [.text], delegate: WorkspaceTabDropDelegate {
                    moveCustomTab(to: tab)
                })
        } else {
            button
        }
    }

    // MARK: - Tab helpers

    private func isEditorDirty(_ tab: WorkspaceTab) -> Bool {
        if case let .editor(id) = tab { return coordinator.editorDirtyState[id] == true }
        return false
    }

    private func tabLabel(_ tab: WorkspaceTab) -> String? {
        switch tab {
        case .info: return NSLocalizedString("Info", comment: "")
        case .agent: return NSLocalizedString("Agent", comment: "")
        case .terminal:
            return nil
        case let .browser(id):
            guard !useCompactTabs else { return nil }
            guard let title = browserTitles[id], !title.isEmpty else { return nil }
            return title.count > 20 ? String(title.prefix(20)) + "..." : title
        case let .editor(id):
            guard let path = editorFilePaths[id] else { return nil }
            let name = (path as NSString).lastPathComponent
            return name.count > 20 ? String(name.prefix(20)) + "..." : name
        }
    }

    private func tabIcon(_ tab: WorkspaceTab) -> String {
        switch tab {
        case .info: return "info.circle"
        case .agent: return "sparkle"
        case .terminal: return "terminal"
        case .browser: return "globe"
        case .editor: return "doc.text"
        }
    }

    private func closeableTabShortcut(_ tab: WorkspaceTab) -> String? {
        guard tab.isCloseable,
              let idx = tabs.firstIndex(of: tab),
              idx < 9 else { return nil }
        return "\(idx + 1)"
    }

    private func tabShortcut(_ tab: WorkspaceTab) -> String? {
        switch tab {
        case .agent: return "\u{21A9}"
        default: return nil
        }
    }

    private func tabDragIdentifier(_ tab: WorkspaceTab) -> String {
        switch tab {
        case let .terminal(id), let .browser(id), let .editor(id):
            return id.uuidString
        case .info:
            return "info"
        case .agent:
            return "agent"
        }
    }

    // MARK: - Tab operations

    private func addTerminal() {
        terminalCount += 1
        let id = derivedUUID(from: context.workstreamID, salt: "terminal-\(terminalCount)")
        let tab = WorkspaceTab.terminal(id)
        tabs.append(tab)
        activeTab = tab
        saveTabSnapshot()
        Telemetry.shared.track("tab_opened", url: "/tab/terminal", title: "Terminal Tab", data: ["kind": "terminal"])
    }

    private func addBrowser() {
        browserCount += 1
        let id = derivedUUID(from: context.workstreamID, salt: "browser-\(browserCount)")
        let tab = WorkspaceTab.browser(id)
        tabs.append(tab)
        activeTab = tab
        saveTabSnapshot()
        Telemetry.shared.track("tab_opened", url: "/tab/browser", title: "Browser Tab", data: ["kind": "browser"])
    }

    private func openEditor() {
        addEditor()
    }

    private func addEditor(filePath: String? = nil) {
        coordinator.createEditorBridgeIfNeeded()
        editorCount += 1
        let id = derivedUUID(from: context.workstreamID, salt: "editor-\(editorCount)")
        if let filePath {
            editorFilePaths[id] = filePath
        }
        let tab = WorkspaceTab.editor(id)
        tabs.append(tab)
        activeTab = tab
        coordinator.startFileTreeWatcherIfNeeded()
        saveTabSnapshot()
        Telemetry.shared.track("tab_opened", url: "/tab/editor", title: "Editor Tab", data: ["kind": "editor"])
    }

    private func closeTab(_ tab: WorkspaceTab) {
        if case let .editor(id) = tab, coordinator.editorDirtyState[id] == true {
            confirmCloseEditor(tab: tab, id: id)
            return
        }
        forceCloseTab(tab)
    }

    private func confirmCloseEditor(tab: WorkspaceTab, id: UUID) {
        let fileName = (editorFilePaths[id] as? NSString)?.lastPathComponent ?? "file"
        let alert = NSAlert()
        alert.messageText = String(
            format: NSLocalizedString("Do you want to save changes to \"%@\"?", comment: ""),
            fileName
        )
        alert.informativeText = NSLocalizedString("Your changes will be lost if you don't save them.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Save", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Don't Save", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alert.alertStyle = .warning

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            Task {
                if let bridge = coordinator.editorBridge,
                   let relativePath = editorFilePaths[id]
                {
                    let fullPath = (context.workingDirectory as NSString)
                        .appendingPathComponent(relativePath)
                    guard let content = await bridge.getContent(modelId: id.uuidString) else { return }
                    do {
                        try content.write(toFile: fullPath, atomically: true, encoding: .utf8)
                    } catch {
                        let errorAlert = NSAlert(error: error)
                        errorAlert.runModal()
                        return
                    }
                }
                forceCloseTab(tab)
            }
        case .alertSecondButtonReturn:
            forceCloseTab(tab)
        default:
            break
        }
    }

    private func forceCloseTab(_ tab: WorkspaceTab) {
        guard let index = tabs.firstIndex(of: tab) else { return }
        tabs.remove(at: index)
        switch tab {
        case let .terminal(id):
            surfaceCache.removeSurface(for: id)
        case let .browser(id):
            surfaceCache.removeWebView(for: id)
        case let .editor(id):
            editorFilePaths.removeValue(forKey: id)
            coordinator.editorDirtyState.removeValue(forKey: id)
            coordinator.editorBridge?.closeModel(modelId: id.uuidString)
        default:
            break
        }
        let hasEditorTabs = tabs.contains { if case .editor = $0 { return true } else { return false } }
        coordinator.stopWatcherIfUnneeded(hasEditorTabs: hasEditorTabs)
        if activeTab == tab {
            let newIndex = min(index, tabs.count - 1)
            activeTab = tabs[newIndex]
        }
        saveTabSnapshot()
    }

    private func moveCustomTab(to targetTab: WorkspaceTab) {
        guard let currentDraggedTab = draggedCustomTab else { return }
        tabs = reorderedCustomTabs(tabs, dragging: currentDraggedTab, to: targetTab)
        draggedCustomTab = nil
    }

    // MARK: - Snapshots

    private func currentTabSnapshot() -> WorkspaceTabSnapshot {
        WorkspaceTabSnapshot(
            tabs: tabs,
            terminalCount: terminalCount,
            browserCount: browserCount,
            editorCount: editorCount,
            activeTab: activeTab,
            browserTitles: browserTitles,
            terminalTitles: terminalTitles,
            editorFilePaths: editorFilePaths,
            runStarted: runStarted,
            runStoppedManually: runStoppedManually
        )
    }

    private func saveTabSnapshot() {
        let snapshot = currentTabSnapshot()
        surfaceCache.saveTabSnapshot(for: context.workstreamID, snapshot: snapshot)
    }

    private func terminalLoadingView(message: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Tab button

private struct WorkspaceTabButton: View {
    let tab: WorkspaceTab
    let label: String?
    let icon: String
    var shortcut: String? = nil
    let isActive: Bool
    var isDirty: Bool = false
    let onSelect: () -> Void
    var onClose: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            if isDirty {
                Circle()
                    .fill(Color.primary.opacity(0.6))
                    .frame(width: 6, height: 6)
            }
            Image(systemName: icon)
                .font(.system(size: 11))
            if let label {
                Text(label)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
            }
            if let shortcut {
                (Text(Image(systemName: "command")) + Text(shortcut))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            if let onClose, isHovering || isActive {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .background(Color.primary.opacity(0.1))
                    .clipShape(Circle())
                    .onTapGesture(perform: onClose)
                    .accessibilityLabel("Close tab")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isActive ? Color.accentColor.opacity(0.15) : (isHovering ? Color.primary.opacity(0.05) : .clear))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .foregroundStyle(isActive ? .primary : .secondary)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Tab bar action button

private struct TabBarActionButton: View {
    let icon: String
    let shortcut: String
    let tooltip: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(shortcut)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(isHovering ? .primary : .tertiary)
            .padding(.horizontal, 6)
            .frame(minHeight: 24)
            .background(isHovering ? Color.primary.opacity(0.08) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.borderless)
        .onHover { isHovering = $0 }
        .help(tooltip)
    }
}

// MARK: - Tab drop delegate

private struct WorkspaceTabDropDelegate: DropDelegate {
    let onDropTab: () -> Void

    func validateDrop(info _: DropInfo) -> Bool {
        true
    }

    func performDrop(info _: DropInfo) -> Bool {
        onDropTab()
        return true
    }
}

// MARK: - Scrollable tab strip

private struct ScrollableTabStrip<TabContent: View>: View {
    let tabs: [WorkspaceTab]
    let activeTab: WorkspaceTab
    @ViewBuilder let tabButton: (WorkspaceTab) -> TabContent

    @State private var contentOverflows = false
    @State private var scrollOffset: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0

    private var canScrollLeft: Bool {
        scrollOffset > 0
    }

    private var canScrollRight: Bool {
        scrollOffset < contentWidth - viewportWidth
    }

    var body: some View {
        HStack(spacing: 0) {
            if contentOverflows, canScrollLeft {
                scrollArrow(direction: .left)
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(tabs, id: \.self) { tab in
                            tabButton(tab)
                                .id(tab)
                        }
                    }
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: ContentWidthKey.self, value: geo.size.width)
                    })
                }
                .onPreferenceChange(ContentWidthKey.self) { width in
                    contentWidth = width
                    checkOverflow()
                }
                .background(GeometryReader { geo in
                    Color.clear
                        .onAppear { viewportWidth = geo.size.width; checkOverflow() }
                        .onChange(of: geo.size.width) { _, new in viewportWidth = new; checkOverflow() }
                })
                .onChange(of: activeTab) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(activeTab, anchor: .center)
                    }
                }
            }

            if contentOverflows, canScrollRight {
                scrollArrow(direction: .right)
            }
        }
    }

    private enum ScrollDirection {
        case left, right
    }

    private func scrollArrow(direction: ScrollDirection) -> some View {
        Button(action: {}) {
            Image(systemName: direction == .left ? "chevron.left" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    private func checkOverflow() {
        contentOverflows = contentWidth > viewportWidth + 1
    }
}

private struct ContentWidthKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

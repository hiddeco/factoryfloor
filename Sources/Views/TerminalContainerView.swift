// ABOUTME: Workspace orchestration shell for a single workstream.
// ABOUTME: Manages Claude command, setup gates, and settings; delegates tab UI to WorkspaceContentView.

import os
import SwiftUI
import WebKit

private let logger = Logger(subsystem: "factoryfloor", category: "surface-cache")

extension Notification.Name {
    static let terminalSurfaceClosed = Notification.Name("factoryfloor.terminalSurfaceClosed")
    static let toggleInfo = Notification.Name("factoryfloor.toggleInfo")
    static let toggleTerminal = Notification.Name("factoryfloor.toggleTerminal")
    static let toggleBrowser = Notification.Name("factoryfloor.toggleBrowser")
    static let focusAgent = Notification.Name("factoryfloor.focusAgent")
    static let closeTerminal = Notification.Name("factoryfloor.closeTerminal")
    static let nextTab = Notification.Name("factoryfloor.nextTab")
    static let prevTab = Notification.Name("factoryfloor.prevTab")
    static let terminalTitleChanged = Notification.Name("factoryfloor.terminalTitleChanged")
    static let toggleEditor = Notification.Name("factoryfloor.toggleEditor")
    static let saveEditor = Notification.Name("factoryfloor.saveEditor")
    static let saveEditorAs = Notification.Name("factoryfloor.saveEditorAs")
}

enum RestorableWorkspaceTab: String, Codable {
    case info
    case agent
    case environment

    init(activeTab: WorkspaceTab) {
        switch activeTab {
        case .agent:
            self = .agent
        case .info, .terminal, .browser, .editor:
            self = .info
        }
    }

    func workspaceTab() -> WorkspaceTab {
        switch self {
        case .info, .environment:
            return .info
        case .agent:
            return .agent
        }
    }
}

enum SetupStateStore {
    private static let userDefaultsKey = "factoryfloor.setupCompleted"

    static func isCompleted(for workstreamID: UUID) -> Bool {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let saved = try? JSONDecoder().decode(Set<String>.self, from: data)
        else { return false }
        return saved.contains(workstreamID.uuidString)
    }

    static func markCompleted(for workstreamID: UUID) {
        var saved: Set<String> = []
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let existing = try? JSONDecoder().decode(Set<String>.self, from: data)
        {
            saved = existing
        }
        saved.insert(workstreamID.uuidString)
        guard let data = try? JSONEncoder().encode(saved) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    static func remove(for workstreamID: UUID) {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              var saved = try? JSONDecoder().decode(Set<String>.self, from: data)
        else { return }
        saved.remove(workstreamID.uuidString)
        guard let encoded = try? JSONEncoder().encode(saved) else { return }
        UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
    }
}

enum WorkspaceStateStore {
    private static let userDefaultsKey = "factoryfloor.workspaceTabs"

    static func load(for workstreamID: UUID) -> RestorableWorkspaceTab? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let saved = try? JSONDecoder().decode([String: RestorableWorkspaceTab].self, from: data)
        else { return nil }
        return saved[workstreamID.uuidString]
    }

    static func save(_ tab: RestorableWorkspaceTab, for workstreamID: UUID) {
        var saved: [String: RestorableWorkspaceTab] = [:]
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let existing = try? JSONDecoder().decode([String: RestorableWorkspaceTab].self, from: data)
        {
            saved = existing
        }
        saved[workstreamID.uuidString] = tab
        guard let data = try? JSONEncoder().encode(saved) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}

func reorderedCustomTabs(_ tabs: [WorkspaceTab], dragging draggedTab: WorkspaceTab, to targetTab: WorkspaceTab) -> [WorkspaceTab] {
    guard draggedTab != targetTab,
          draggedTab.isCloseable,
          targetTab.isCloseable,
          let sourceIndex = tabs.firstIndex(of: draggedTab),
          let targetIndex = tabs.firstIndex(of: targetTab)
    else {
        return tabs
    }

    var reordered = tabs
    let movedTab = reordered.remove(at: sourceIndex)
    let insertionIndex = targetIndex > sourceIndex ? targetIndex - 1 : targetIndex
    reordered.insert(movedTab, at: insertionIndex)
    return reordered
}

/// A tab in the workspace. Info and Agent are permanent; terminals and browsers are closeable.
enum WorkspaceTab: Hashable {
    case info
    case agent
    case terminal(UUID)
    case browser(UUID)
    case editor(UUID)

    var isCloseable: Bool {
        switch self {
        case .info, .agent: return false
        case .terminal, .browser, .editor: return true
        }
    }
}

/// Captured workspace tab state for a workstream, used to survive navigation.
struct WorkspaceTabSnapshot {
    var tabs: [WorkspaceTab]
    var terminalCount: Int
    var browserCount: Int
    var editorCount: Int
    var activeTab: WorkspaceTab
    var browserTitles: [UUID: String]
    var terminalTitles: [UUID: String]
    var editorFilePaths: [UUID: String]
    var runStarted: Bool
    var runStoppedManually: Bool

    /// Returns a copy with dead terminal tabs removed.
    /// Browser and editor tabs are kept regardless (they don't use terminal surfaces).
    func reconciled(liveSurfaceIDs: Set<UUID>) -> WorkspaceTabSnapshot {
        let filteredTabs = tabs.filter { tab in
            if case let .terminal(id) = tab {
                return liveSurfaceIDs.contains(id)
            }
            return true
        }
        let resolvedActiveTab = filteredTabs.contains(activeTab) ? activeTab : .agent
        return WorkspaceTabSnapshot(
            tabs: filteredTabs,
            terminalCount: terminalCount,
            browserCount: browserCount,
            editorCount: editorCount,
            activeTab: resolvedActiveTab,
            browserTitles: browserTitles,
            terminalTitles: terminalTitles,
            editorFilePaths: editorFilePaths,
            runStarted: runStarted,
            runStoppedManually: runStoppedManually
        )
    }
}

func startupWorkspaceTabState(snapshot: WorkspaceTabSnapshot?, savedTab: RestorableWorkspaceTab?) -> WorkspaceTabSnapshot {
    if let snapshot {
        // Filter out any persisted environment tabs from before the merge
        let filteredTabs = snapshot.tabs.filter { tab in
            if case .info = tab { return true }
            if case .agent = tab { return true }
            if case .terminal = tab { return true }
            if case .browser = tab { return true }
            return false
        }
        var cleaned = snapshot
        cleaned.tabs = filteredTabs
        if !cleaned.tabs.contains(cleaned.activeTab) {
            cleaned.activeTab = .info
        }
        return cleaned
    }

    let tabs: [WorkspaceTab] = [.info, .agent]
    return WorkspaceTabSnapshot(
        tabs: tabs,
        terminalCount: 0,
        browserCount: 0,
        editorCount: 0,
        activeTab: (savedTab ?? .info).workspaceTab(),
        browserTitles: [:],
        terminalTitles: [:],
        editorFilePaths: [:],
        runStarted: false,
        runStoppedManually: false
    )
}

func workspaceEnvironmentVariables(
    workstreamID: UUID,
    projectName: String,
    workstreamName: String,
    projectDirectory: String,
    workingDirectory: String,
    port: Int,
    agentTeams: Bool,
    defaultBranch: String,
    scriptSource: String?
) -> [String: String] {
    WorkstreamEnvironment.variables(
        workstreamID: workstreamID,
        projectName: projectName,
        workstreamName: workstreamName,
        projectDirectory: projectDirectory,
        workingDirectory: workingDirectory,
        port: port,
        agentTeams: agentTeams,
        defaultBranch: defaultBranch,
        scriptSource: scriptSource
    )
}

enum TerminalSessionMode: Equatable {
    case standard
    case tmux
    case waitingForTools

    static func resolve(tmuxModeEnabled: Bool, isDetectingTools: Bool, tmuxInstalled: Bool) -> Self {
        if tmuxModeEnabled {
            if isDetectingTools {
                return .waitingForTools
            }
            if tmuxInstalled {
                return .tmux
            }
        }
        return .standard
    }
}

enum SetupGateState: Equatable {
    case notNeeded
    case running
    case failed
    case completed
}

// MARK: - TerminalContainerView

struct TerminalContainerView: View {
    let workstreamID: UUID
    let workingDirectory: String
    let projectDirectory: String
    let projectName: String
    let workstreamName: String
    let bypassPermissions: Bool
    let isActive: Bool

    @EnvironmentObject var surfaceCache: TerminalSurfaceCache
    @EnvironmentObject var appEnv: AppEnvironment
    @AppStorage("factoryfloor.defaultBrowser") private var defaultBrowser: String = ""
    @AppStorage("factoryfloor.tmuxMode") private var tmuxMode: Bool = false
    @AppStorage("factoryfloor.agentTeams") private var agentTeams: Bool = false
    @AppStorage("factoryfloor.autoRenameBranch") private var autoRenameBranch: Bool = false
    @AppStorage("factoryfloor.allowOutsideWorktree") private var allowOutsideWorktree: Bool = false
    @AppStorage("factoryfloor.quickActionDebug") private var quickActionDebug: Bool = false
    let scriptConfig: ScriptConfig
    @State private var cachedClaudeCommand: String?
    @State private var cachedSetupGateCommand: String?
    @StateObject private var portDetector: PortDetector
    @State private var runStoppedManually = false
    @State private var runStarted = false
    @State private var workspaceStarted = false
    @State private var defaultBranch = "main"
    @State private var setupGateState: SetupGateState = .notNeeded

    private let initialTabState: WorkspaceTabSnapshot

    init(
        workstreamID: UUID,
        workingDirectory: String,
        projectDirectory: String,
        projectName: String,
        workstreamName: String,
        bypassPermissions: Bool,
        isActive: Bool,
        scriptConfig: ScriptConfig = .empty,
        initialTabState: WorkspaceTabSnapshot = startupWorkspaceTabState(snapshot: nil, savedTab: nil)
    ) {
        self.workstreamID = workstreamID
        self.workingDirectory = workingDirectory
        self.projectDirectory = projectDirectory
        self.projectName = projectName
        self.workstreamName = workstreamName
        self.bypassPermissions = bypassPermissions
        self.isActive = isActive
        self.initialTabState = initialTabState
        self.scriptConfig = scriptConfig
        if let setup = scriptConfig.setup {
            _cachedSetupGateCommand = State(
                initialValue: scriptCommand(script: setup, role: "setup")
            )
        }
        _runStoppedManually = State(initialValue: initialTabState.runStoppedManually)
        _runStarted = State(initialValue: initialTabState.runStarted)
        _portDetector = StateObject(wrappedValue: PortDetector(workstreamID: workstreamID))
    }

    // MARK: - Computed properties

    private var claudeID: UUID {
        workstreamID
    }

    private var setupGateID: UUID {
        derivedUUID(from: workstreamID, salt: "setup-gate")
    }

    private var quickActionRunner: QuickActionRunner {
        surfaceCache.quickActionRunner(for: workstreamID)
    }

    private var sessionMode: TerminalSessionMode {
        TerminalSessionMode.resolve(
            tmuxModeEnabled: tmuxMode,
            isDetectingTools: appEnv.isDetecting,
            tmuxInstalled: appEnv.toolStatus.tmux.isInstalled
        )
    }

    private var useTmux: Bool {
        sessionMode == .tmux
    }

    private var workstreamPort: Int {
        PortAllocator.port(for: workingDirectory)
    }

    private var portSubtitle: String {
        let label = appEnv.taskDescription(for: workingDirectory) ?? projectName
        if let port = portDetector.selectedPort {
            return "\(label) · localhost:\(port) · \u{2318}B for browser"
        }
        return label
    }

    private var browserDefaultURL: String {
        let port = portDetector.selectedPort ?? workstreamPort
        return "http://localhost:\(port)/"
    }

    private var branchPR: GitHubPR? {
        guard let branch = appEnv.branchName(for: workingDirectory) else { return nil }
        return appEnv.githubPR(for: projectDirectory, branch: branch)
    }

    private var envVars: [String: String] {
        workspaceEnvironmentVariables(
            workstreamID: workstreamID,
            projectName: projectName,
            workstreamName: workstreamName,
            projectDirectory: projectDirectory,
            workingDirectory: workingDirectory,
            port: workstreamPort,
            agentTeams: agentTeams,
            defaultBranch: defaultBranch,
            scriptSource: scriptConfig.source
        )
    }

    /// Env vars for plain terminal tabs. Clears tmux vars to prevent inheritance.
    private var terminalEnvVars: [String: String] {
        var vars = envVars
        vars["TMUX"] = ""
        vars["TMUX_PANE"] = ""
        return vars
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceContentView(
                context: WorkspaceContext(
                    workstreamID: workstreamID,
                    workingDirectory: workingDirectory,
                    projectDirectory: projectDirectory,
                    projectName: projectName,
                    workstreamName: workstreamName
                ),
                isActive: isActive,
                workspaceStarted: workspaceStarted,
                state: WorkspaceSessionState(
                    claudeCommand: cachedClaudeCommand,
                    claudeID: claudeID,
                    sessionMode: sessionMode,
                    scriptConfig: scriptConfig,
                    browserDefaultURL: browserDefaultURL,
                    branchPR: branchPR,
                    envVars: envVars,
                    terminalEnvVars: terminalEnvVars,
                    setupGateCommand: cachedSetupGateCommand
                ),
                setupGateState: $setupGateState,
                runStoppedManually: $runStoppedManually,
                runStarted: $runStarted,
                onContinueAfterSetup: { launchAgentAfterSetup() },
                initialTabState: initialTabState
            )
            if quickActionDebug {
                Divider()
                QuickActionDebugView(runner: quickActionRunner)
            }
        }
        .task(id: workstreamID) {
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            let branch = await Task.detached {
                GitOperations.defaultBranch(at: projectDirectory)
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run {
                startWorkspace(defaultBranch: branch)
            }
        }
        .onChange(of: tmuxMode) { rebuildCachedCommands() }
        .onChange(of: bypassPermissions) { rebuildCachedCommands() }
        .onChange(of: autoRenameBranch) { rebuildCachedCommands() }
        .onChange(of: allowOutsideWorktree) { rebuildCachedCommands() }
        .onChange(of: workstreamName) { rebuildCachedCommands() }
        .onChange(of: appEnv.isDetecting) {
            rebuildCachedCommands()
            if isActive { preloadSurfaces() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .terminalChildExited)) { notification in
            guard let surfaceID = notification.object as? UUID, surfaceID == setupGateID,
                  let exitCode = notification.userInfo?["exitCode"] as? Int32
            else { return }
            handleSetupChildExited(exitCode: exitCode)
        }
        .onReceive(NotificationCenter.default.publisher(for: .terminalTabExited)) { notification in
            guard let surfaceID = notification.object as? UUID else { return }
            if surfaceID == setupGateID, setupGateState == .failed {
                launchAgentAfterSetup()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .terminalActivity)) { notification in
            guard isActive else { return }
            guard let wsID = notification.object as? UUID, wsID == workstreamID else { return }
            appEnv.refreshWorktreeState(for: workingDirectory, projectDirectory: projectDirectory)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openExternalBrowser)) { _ in
            guard isActive else { return }
            guard let url = URL(string: browserDefaultURL) else { return }
            if defaultBrowser.isEmpty {
                NSWorkspace.shared.open(url)
            } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: defaultBrowser) {
                NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(url)
            }
        }
        .toolbar {
            if isActive {
                ToolbarItemGroup(placement: .primaryAction) {
                    if let githubURL = appEnv.githubURL(for: projectDirectory) {
                        Button {
                            NSWorkspace.shared.open(githubURL)
                        } label: {
                            Label(NSLocalizedString("GitHub", comment: ""), image: "github")
                                .labelStyle(.iconOnly)
                        }
                        .help("Open on GitHub")
                    }

                    GitHubActionMenu(
                        runner: quickActionRunner,
                        claudePath: appEnv.toolStatus.claude.path,
                        ghPath: appEnv.toolStatus.gh.path,
                        workingDirectory: workingDirectory,
                        branchName: appEnv.branchName(for: workingDirectory),
                        bypassPermissions: bypassPermissions,
                        worktreeState: appEnv.worktreeState(for: workingDirectory),
                        hasGitHubRemote: appEnv.hasGitHubRemote(projectDirectory),
                        branchPR: branchPR
                    )
                }
            }
        }
    }

    // MARK: - Claude command

    private func buildClaudeCommand() -> String? {
        guard let basePath = appEnv.toolStatus.claude.path else { return nil }
        let sessionID = workstreamID.uuidString.lowercased()

        var systemPromptParts: [String] = []
        if !allowOutsideWorktree {
            systemPromptParts.append(SystemPrompts.restrictToWorktreePrompt(worktreePath: workingDirectory))
        }
        if autoRenameBranch {
            systemPromptParts.append(SystemPrompts.autoRenameBranchPrompt)
        }
        let combinedSystemPrompt = systemPromptParts.isEmpty ? nil : systemPromptParts.joined(separator: "\n\n")

        var resume = CommandBuilder(basePath)
        resume.option("--resume", sessionID)
        if appEnv.toolStatus.claudeSupportsSessionName {
            resume.option("--name", workstreamName)
        }
        if useTmux { resume.flag("--teammate-mode"); resume.arg("tmux") }
        if bypassPermissions { resume.flag("--dangerously-skip-permissions") }
        if let combinedSystemPrompt {
            resume.option("--append-system-prompt", combinedSystemPrompt)
        }

        var fresh = CommandBuilder(basePath)
        fresh.option("--session-id", sessionID)
        if appEnv.toolStatus.claudeSupportsSessionName {
            fresh.option("--name", workstreamName)
        }
        if useTmux { fresh.flag("--teammate-mode"); fresh.arg("tmux") }
        if bypassPermissions { fresh.flag("--dangerously-skip-permissions") }
        if let combinedSystemPrompt {
            fresh.option("--append-system-prompt", combinedSystemPrompt)
        }

        let cmd = CommandBuilder.withFallback(
            resume.command, fresh.command,
            message: "Starting new session..."
        )

        let finalCommand: String
        var intermediates = [resume.command, fresh.command, cmd]
        if useTmux, let tmuxPath = appEnv.toolStatus.tmux.path {
            let session = TmuxSession.sessionName(project: projectName, workstream: workstreamName, role: "agent")
            finalCommand = TmuxSession.wrapCommand(tmuxPath: tmuxPath, sessionName: session, command: cmd, environmentVars: envVars, respawnOnExit: true)
            intermediates.append(finalCommand)
        } else {
            finalCommand = cmd
        }

        LaunchLogger.log(LaunchLogEntry(
            workstreamID: workstreamID,
            event: "agent-start",
            finalCommand: finalCommand,
            intermediateCommands: intermediates,
            environmentVariables: envVars,
            workingDirectory: workingDirectory,
            toolPaths: LaunchLogEntry.ToolPaths(
                claude: appEnv.toolStatus.claude.path,
                tmux: appEnv.toolStatus.tmux.path,
                ffRun: RunLauncher.executableURL()?.path
            ),
            settings: LaunchLogEntry.Settings(
                tmuxMode: tmuxMode,
                bypassPermissions: bypassPermissions,
                agentTeams: agentTeams,
                autoRenameBranch: autoRenameBranch,
                allowOutsideWorktree: allowOutsideWorktree
            ),
            shell: CommandBuilder.userShell
        ))

        return finalCommand
    }

    private func rebuildCachedCommands() {
        cachedClaudeCommand = buildClaudeCommand()
    }

    // MARK: - Setup gate

    private func handleSetupChildExited(exitCode: Int32) {
        guard setupGateState == .running else { return }
        if exitCode == 0 {
            launchAgentAfterSetup()
        } else {
            setupGateState = .failed
        }
    }

    private func launchAgentAfterSetup() {
        SetupStateStore.markCompleted(for: workstreamID)
        surfaceCache.removeSurface(for: setupGateID)
        setupGateState = .completed
        surfaceCache.respawnableIDs.insert(claudeID)
        preloadSurfaces()
        // Occlusion is updated by WorkspaceContentView's .onChange(of: setupGateState),
        // which fires before the next render pass. We cannot call
        // updateOcclusion here because we don't know WorkspaceContentView's active tab.
    }

    // MARK: - Workspace lifecycle

    @MainActor
    private func startWorkspace(defaultBranch: String) {
        workspaceStarted = true
        self.defaultBranch = defaultBranch
        quickActionRunner.onSuccess = { action in
            appEnv.refreshWorktreeState(for: workingDirectory, projectDirectory: projectDirectory)
            if let branch = appEnv.branchName(for: workingDirectory) {
                if action == .closePR {
                    appEnv.clearBranchPR(for: projectDirectory, branch: branch)
                }
                if action == .createPR || action == .closePR {
                    appEnv.refreshGitHubInfo(for: projectDirectory, branch: branch)
                }
            }
        }
        appEnv.refreshWorktreeState(for: workingDirectory, projectDirectory: projectDirectory)
        rebuildCachedCommands()
        if scriptConfig.setup != nil, !SetupStateStore.isCompleted(for: workstreamID) {
            setupGateState = .running
        } else {
            setupGateState = .notNeeded
            surfaceCache.respawnableIDs.insert(claudeID)
        }
        preloadSurfaces()
    }

    /// Pre-create terminal surfaces so they start running before their tab is visible.
    private func preloadSurfaces() {
        guard sessionMode != .waitingForTools else { return }
        guard let app = TerminalApp.shared.app else { return }

        if setupGateState == .running {
            if let cmd = cachedSetupGateCommand {
                _ = surfaceCache.surface(
                    for: setupGateID,
                    app: app,
                    workingDirectory: workingDirectory,
                    command: cmd,
                    environmentVars: terminalEnvVars,
                    waitAfterCommand: false
                )
            }
        } else {
            if let cmd = cachedClaudeCommand {
                _ = surfaceCache.surface(
                    for: claudeID,
                    app: app,
                    workingDirectory: workingDirectory,
                    command: cmd,
                    environmentVars: envVars
                )
            }
        }
    }
}

// MARK: - SingleTerminalView

struct SingleTerminalView: View {
    let surfaceID: UUID
    let workingDirectory: String
    var command: String?
    var isFocused: Bool = true
    var environmentVars: [String: String] = [:]

    @EnvironmentObject var surfaceCache: TerminalSurfaceCache

    var body: some View {
        if let failedCommand = surfaceCache.failedSurfaces[surfaceID] {
            SurfaceErrorView(command: failedCommand) {
                surfaceCache.retrySurface(for: surfaceID)
            }
        } else {
            GeometryReader { geo in
                TerminalSurfaceView(
                    surfaceID: surfaceID,
                    workingDirectory: workingDirectory,
                    command: command,
                    isFocused: isFocused,
                    environmentVars: environmentVars,
                    size: geo.size
                )
            }
        }
    }
}

private struct SurfaceErrorView: View {
    let command: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Terminal failed to start")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(command)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(3)
                .truncationMode(.middle)
                .padding(.horizontal, 40)
            Button("Retry", action: onRetry)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TerminalSurfaceView: NSViewRepresentable {
    let surfaceID: UUID
    let workingDirectory: String
    var command: String?
    var isFocused: Bool = true
    var environmentVars: [String: String] = [:]
    var size: CGSize

    @EnvironmentObject var surfaceCache: TerminalSurfaceCache

    func makeNSView(context _: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        return container
    }

    func updateNSView(_ container: NSView, context _: Context) {
        guard let app = TerminalApp.shared.app else { return }

        let terminalView = surfaceCache.surface(
            for: surfaceID,
            app: app,
            workingDirectory: workingDirectory,
            command: command,
            environmentVars: environmentVars
        )

        if terminalView.superview !== container {
            terminalView.removeFromSuperview()
            container.subviews.forEach { $0.removeFromSuperview() }
            container.addSubview(terminalView)
            terminalView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                terminalView.topAnchor.constraint(equalTo: container.topAnchor),
                terminalView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                terminalView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                terminalView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
        }

        // Explicitly push the SwiftUI-measured size to the Ghostty surface.
        // SwiftUI does not reliably call NSView.setFrameSize on resize
        // (see Ghostty SurfaceView.swift:613-616), so we drive it from
        // the GeometryReader instead.
        if terminalView.window != nil {
            terminalView.notifySizeChanged(size)
        }

        if isFocused {
            DispatchQueue.main.async {
                terminalView.window?.makeFirstResponder(terminalView)
            }
        }
    }
}

// MARK: - GitHub actions

private struct GitHubActionMenu: View {
    @ObservedObject var runner: QuickActionRunner
    let claudePath: String?
    let ghPath: String?
    let workingDirectory: String
    let branchName: String?
    let bypassPermissions: Bool
    let worktreeState: WorktreeState
    let hasGitHubRemote: Bool
    let branchPR: GitHubPR?

    private var prState: String? {
        branchPR?.state
    }

    private var hasOpenPR: Bool {
        prState == "OPEN"
    }

    private var isMerged: Bool {
        prState == "MERGED"
    }

    /// The most relevant next action to move the workflow forward.
    private var primaryAction: PrimaryAction? {
        if isMerged {
            return nil
        }
        if hasOpenPR {
            if worktreeState.hasUncommittedChanges {
                return .quickAction(.commit)
            }
            if worktreeState.hasUnpushedCommits, worktreeState.hasRemote {
                return .quickAction(.push)
            }
            if let pr = branchPR {
                return .openPR(pr)
            }
        }
        if prState == nil, hasGitHubRemote, worktreeState.hasBranchCommits {
            return .quickAction(.createPR)
        }
        if worktreeState.hasUncommittedChanges {
            return .quickAction(.commit)
        }
        if worktreeState.hasUnpushedCommits, worktreeState.hasRemote {
            return .quickAction(.push)
        }
        return nil
    }

    /// Secondary actions shown in the dropdown, excluding the primary.
    private var secondaryActions: [PrimaryAction] {
        guard let primary = primaryAction else { return [] }
        var actions: [PrimaryAction] = []

        if worktreeState.hasUncommittedChanges {
            actions.append(.quickAction(.commit))
        }
        if worktreeState.hasUnpushedCommits, worktreeState.hasRemote {
            actions.append(.quickAction(.push))
        }
        if prState == nil, hasGitHubRemote, worktreeState.hasBranchCommits {
            actions.append(.quickAction(.createPR))
        }
        if let pr = branchPR, hasOpenPR {
            actions.append(.openPR(pr))
            actions.append(.quickAction(.closePR))
        }

        return actions.filter { $0 != primary }
    }

    private var isRunning: Bool {
        if case .running = runner.state { return true }
        return false
    }

    private func isRunningAction(_ action: QuickAction) -> Bool {
        if case let .running(a) = runner.state { return a == action }
        return false
    }

    private func resultState(for action: QuickAction) -> QuickActionState? {
        switch runner.state {
        case let .succeeded(a) where a == action: return runner.state
        case let .failed(a) where a == action: return runner.state
        default: return nil
        }
    }

    private func disabledReason(for action: QuickAction) -> String? {
        if action.usesLLM {
            if claudePath == nil {
                return NSLocalizedString("Claude Code is not installed.", comment: "")
            }
            if !bypassPermissions {
                return NSLocalizedString("Enable \"Bypass permission prompts\" in Settings.", comment: "")
            }
        }
        if action == .closePR, ghPath == nil {
            return NSLocalizedString("gh CLI is not installed.", comment: "")
        }
        return nil
    }

    private func runAction(_ action: QuickAction) {
        guard disabledReason(for: action) == nil else { return }
        runner.run(
            action: action,
            claudePath: claudePath,
            ghPath: ghPath,
            workingDirectory: workingDirectory,
            branchName: branchName
        )
    }

    private func executePrimary(_ action: PrimaryAction) {
        guard !isRunning else { return }
        switch action {
        case let .quickAction(qa):
            runAction(qa)
        case let .openPR(pr):
            if let url = URL(string: pr.url) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @ViewBuilder
    private func label(for action: PrimaryAction) -> some View {
        switch action {
        case let .quickAction(qa):
            if isRunningAction(qa) {
                ProgressView()
                    .controlSize(.mini)
            } else if case .succeeded = resultState(for: qa) {
                Label(qa.label, systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
            } else if case .failed = resultState(for: qa) {
                Label(qa.label, systemImage: "xmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.red)
            } else {
                Label(qa.label, systemImage: qa.icon)
                    .labelStyle(.titleAndIcon)
            }
        case let .openPR(pr):
            Label(
                String(format: NSLocalizedString("Open #%d", comment: ""), pr.number),
                systemImage: "arrow.up.forward"
            )
            .labelStyle(.titleAndIcon)
        }
    }

    var body: some View {
        if let primary = primaryAction {
            let secondary = secondaryActions
            if secondary.isEmpty {
                Button { executePrimary(primary) } label: { label(for: primary) }
                    .disabled(isRunning || primaryDisabled(primary))
                    .help(primaryHelp(primary))
            } else {
                Menu {
                    ForEach(secondary) { action in
                        switch action {
                        case let .quickAction(qa):
                            Button { runAction(qa) } label: {
                                Label(qa.label, systemImage: qa.icon)
                            }
                            .disabled(isRunning || disabledReason(for: qa) != nil)
                        case let .openPR(pr):
                            Button {
                                if let url = URL(string: pr.url) {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                Label(
                                    String(format: NSLocalizedString("Open #%d", comment: ""), pr.number),
                                    systemImage: "arrow.up.forward"
                                )
                            }
                        }
                    }
                } label: {
                    label(for: primary)
                } primaryAction: {
                    executePrimary(primary)
                }
                .disabled(isRunning)
                .menuIndicator(.hidden)
                .help(primaryHelp(primary))
            }
        }
    }

    private func primaryDisabled(_ action: PrimaryAction) -> Bool {
        if case let .quickAction(qa) = action {
            return disabledReason(for: qa) != nil
        }
        return false
    }

    private func primaryHelp(_ action: PrimaryAction) -> String {
        if case let .quickAction(qa) = action {
            return disabledReason(for: qa) ?? qa.label
        }
        if case let .openPR(pr) = action {
            return pr.title
        }
        return ""
    }
}

/// Represents either a quick action or opening a PR in the browser.
private enum PrimaryAction: Equatable, Identifiable {
    case quickAction(QuickAction)
    case openPR(GitHubPR)

    var id: String {
        switch self {
        case let .quickAction(qa): return qa.id
        case let .openPR(pr): return "openPR-\(pr.number)"
        }
    }
}

// MARK: - Quick action debug

private struct QuickActionDebugView: View {
    @ObservedObject var runner: QuickActionRunner

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Quick Action Log")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                if !runner.log.isEmpty {
                    Button("Clear") { runner.clearLog() }
                        .font(.system(size: 10))
                        .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            if runner.log.isEmpty {
                Text("No quick actions run yet.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(runner.log) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(Self.timeFormatter.string(from: entry.timestamp))
                                        .foregroundStyle(.tertiary)
                                    Text(entry.action.label)
                                        .foregroundStyle(.primary)
                                    if let code = entry.exitCode {
                                        Text("exit \(code)")
                                            .foregroundStyle(code == 0 ? .green : .red)
                                    } else {
                                        ProgressView()
                                            .controlSize(.mini)
                                    }
                                }
                                .font(.system(size: 11, weight: .medium, design: .monospaced))

                                Text("$ " + entry.command)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)

                                if !entry.output.isEmpty {
                                    Text(entry.output)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.primary)
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(height: 200)
        .background(.background)
    }
}

// MARK: - Surface cache

extension Notification.Name {
    static let terminalTabExited = Notification.Name("factoryfloor.terminalTabExited")
}

@MainActor
final class TerminalSurfaceCache: ObservableObject {
    private var surfaces: [UUID: TerminalView] = [:]
    private var surfaceParams: [UUID: SurfaceParams] = [:]
    private var tabSnapshots: [UUID: WorkspaceTabSnapshot] = [:]
    private var webViews: [UUID: WKWebView] = [:]
    private var quickActionRunners: [UUID: QuickActionRunner] = [:]
    /// Surface IDs that should respawn when closed (e.g., the agent).
    var respawnableIDs: Set<UUID> = []
    /// Guards against concurrent respawns for the same surface ID.
    private var respawning = Set<UUID>()
    /// Surface IDs where creation failed, with the command that was attempted.
    private(set) var failedSurfaces: [UUID: String] = [:]
    /// Tracks when each surface was created, for detecting immediate process death.
    private var creationTimes: [UUID: Date] = [:]
    /// Surfaces that died within this interval after creation are treated as launch failures.
    private static let healthCheckWindow: TimeInterval = 2.0

    struct SurfaceParams {
        let workingDirectory: String
        let command: String?
        let initialInput: String?
        let environmentVars: [String: String]
        let waitAfterCommand: Bool
    }

    init() {
        NotificationCenter.default.addObserver(
            forName: .terminalSurfaceClosed,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let closedView = notification.object as? TerminalView else { return }
            Task { @MainActor in
                self.handleSurfaceClosed(closedView)
            }
        }
    }

    /// Marks surfaces in the given set as visible; all others are occluded.
    /// Pass nil to mark all surfaces as visible.
    func updateOcclusion(visibleSurfaceIDs: Set<UUID>?) {
        for (id, view) in surfaces {
            let visible = visibleSurfaceIDs.map { $0.contains(id) } ?? true
            view.setVisible(visible)
        }
    }

    func surface(for id: UUID, app: ghostty_app_t, workingDirectory: String, command: String? = nil, initialInput: String? = nil, environmentVars: [String: String] = [:], waitAfterCommand: Bool = true) -> TerminalView {
        if let existing = surfaces[id] {
            existing.workstreamID = id
            return existing
        }
        let view = TerminalView(app: app, workingDirectory: workingDirectory, command: command, initialInput: initialInput, environmentVars: environmentVars, waitAfterCommand: waitAfterCommand)
        view.workstreamID = id
        surfaces[id] = view
        surfaceParams[id] = SurfaceParams(workingDirectory: workingDirectory, command: command, initialInput: initialInput, environmentVars: environmentVars, waitAfterCommand: waitAfterCommand)
        if view.surface == nil {
            logger.error("Surface creation failed for \(id) command=\(command ?? "<shell>")")
            failedSurfaces[id] = command ?? "(default shell)"
            objectWillChange.send()
        } else {
            creationTimes[id] = Date()
        }
        return view
    }

    /// Retry creating a surface that previously failed.
    func retrySurface(for id: UUID) {
        guard let params = surfaceParams[id],
              let app = TerminalApp.shared.app else { return }
        logger.detailed("Retrying surface creation for \(id)")
        if let view = surfaces.removeValue(forKey: id) {
            view.destroy()
        }
        failedSurfaces.removeValue(forKey: id)
        let view = TerminalView(app: app, workingDirectory: params.workingDirectory, command: params.command, initialInput: params.initialInput, environmentVars: params.environmentVars, waitAfterCommand: params.waitAfterCommand)
        view.workstreamID = id
        surfaces[id] = view
        if view.surface == nil {
            logger.error("Surface retry failed for \(id)")
            failedSurfaces[id] = params.command ?? "(default shell)"
        } else {
            creationTimes[id] = Date()
        }
        objectWillChange.send()
    }

    func webView(for id: UUID) -> WKWebView {
        if let existing = webViews[id] { return existing }
        let view = BrowserWebView()
        webViews[id] = view
        return view
    }

    func quickActionRunner(for workstreamID: UUID) -> QuickActionRunner {
        if let existing = quickActionRunners[workstreamID] {
            return existing
        }
        let runner = QuickActionRunner()
        quickActionRunners[workstreamID] = runner
        return runner
    }

    func removeWebView(for id: UUID) {
        webViews.removeValue(forKey: id)
    }

    func removeSurface(for id: UUID) {
        if let view = surfaces.removeValue(forKey: id) {
            view.destroy()
        }
        surfaceParams.removeValue(forKey: id)
        failedSurfaces.removeValue(forKey: id)
        creationTimes.removeValue(forKey: id)
    }

    func removeWorkstreamSurfaces(for workstreamID: UUID) {
        tabSnapshots.removeValue(forKey: workstreamID)
        if let runner = quickActionRunners.removeValue(forKey: workstreamID) {
            runner.cancel()
        }
        // Remove agent surface
        removeSurface(for: workstreamID)
        // Build a set of all possible derived IDs and remove matches
        var derivedIDs = Set<UUID>()
        for prefix in ["terminal", "browser", "editor", "env-setup", "env-run"] {
            for i in 0 ... 99 {
                derivedIDs.insert(derivedUUID(from: workstreamID, salt: "\(prefix)-\(i)"))
            }
        }
        for id in derivedIDs {
            if surfaces[id] != nil { removeSurface(for: id) }
            if webViews[id] != nil { removeWebView(for: id) }
        }
    }

    private func handleSurfaceClosed(_ closedView: TerminalView) {
        guard let (id, _) = surfaces.first(where: { $0.value === closedView }) else { return }

        // Check if the surface died immediately after creation (launch failure).
        let diedImmediately: Bool
        if let created = creationTimes[id] {
            let age = Date().timeIntervalSince(created)
            diedImmediately = age < Self.healthCheckWindow
            if diedImmediately {
                logger.error("Surface \(id) died after \(String(format: "%.1f", age))s, treating as launch failure")
            }
        } else {
            diedImmediately = false
        }

        if respawnableIDs.contains(id) {
            // If the surface died immediately, show error state instead of respawning in a loop.
            if diedImmediately {
                let command = surfaceParams[id]?.command ?? "(default shell)"
                failedSurfaces[id] = command
                objectWillChange.send()
                return
            }

            guard !respawning.contains(id) else {
                logger.detailed("Skipping concurrent respawn for surface \(id)")
                return
            }
            guard let params = surfaceParams[id],
                  let app = TerminalApp.shared.app else { return }

            respawning.insert(id)
            surfaces.removeValue(forKey: id)
            let newView = TerminalView(app: app, workingDirectory: params.workingDirectory, command: params.command, initialInput: params.initialInput, environmentVars: params.environmentVars, waitAfterCommand: params.waitAfterCommand)
            newView.workstreamID = id
            surfaces[id] = newView
            respawning.remove(id)
            if newView.surface == nil {
                logger.error("Respawn failed for surface \(id)")
                failedSurfaces[id] = params.command ?? "(default shell)"
            } else {
                creationTimes[id] = Date()
                logger.detailed("Respawned surface \(id)")
            }
            objectWillChange.send()
        } else if diedImmediately {
            // Terminal tab died immediately: show error instead of closing the tab.
            let command = surfaceParams[id]?.command ?? "(default shell)"
            failedSurfaces[id] = command
            objectWillChange.send()
        } else {
            removeSurface(for: id)
            NotificationCenter.default.post(name: .terminalTabExited, object: id)
        }
    }

    // MARK: - Text injection

    /// Send text to a terminal surface as if it were typed.
    func sendText(to surfaceID: UUID, text: String) {
        guard let view = surfaces[surfaceID],
              let surface = view.surface else { return }
        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(text.utf8.count))
        }
    }

    // MARK: - Workspace tab snapshots

    func saveTabSnapshot(for workstreamID: UUID, snapshot: WorkspaceTabSnapshot) {
        tabSnapshots[workstreamID] = snapshot
    }

    func restoreTabSnapshot(for workstreamID: UUID) -> WorkspaceTabSnapshot? {
        guard let snapshot = tabSnapshots[workstreamID] else { return nil }
        let liveSurfaceIDs = Set(surfaces.keys)
        return snapshot.reconciled(liveSurfaceIDs: liveSurfaceIDs)
    }

    func removeTabSnapshot(for workstreamID: UUID) {
        tabSnapshots.removeValue(forKey: workstreamID)
    }
}

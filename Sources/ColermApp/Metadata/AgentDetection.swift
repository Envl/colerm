import Foundation

enum AgentKind: String, CaseIterable, Equatable, Sendable {
    case claudeCode
    case codex
    case pi
    case opencode
    case grok
    case factoryDroid
    case agy
    case amp
    case gemini
    case cursor
    case copilot
    case qwen
    case kimi
    case kiro
    case muse

    var displayName: String {
        switch self {
        case .claudeCode:
            return "Claude Code"
        case .codex:
            return "Codex"
        case .pi:
            return "Pi"
        case .opencode:
            return "OpenCode"
        case .grok:
            return "Grok"
        case .factoryDroid:
            return "Factory Droid"
        case .agy:
            return "Antigravity"
        case .amp:
            return "Amp"
        case .gemini:
            return "Gemini CLI"
        case .cursor:
            return "Cursor CLI"
        case .copilot:
            return "GitHub Copilot CLI"
        case .qwen:
            return "Qwen Code"
        case .kimi:
            return "Kimi CLI"
        case .kiro:
            return "Kiro CLI"
        case .muse:
            return "Muse Code"
        }
    }

    var shortName: String {
        switch self {
        case .claudeCode:
            return "Claude"
        case .codex:
            return "Codex"
        case .pi:
            return "Pi"
        case .opencode:
            return "OpenCode"
        case .grok:
            return "Grok"
        case .factoryDroid:
            return "Droid"
        case .agy:
            return "AGY"
        case .amp:
            return "Amp"
        case .gemini:
            return "Gemini"
        case .cursor:
            return "Cursor"
        case .copilot:
            return "Copilot"
        case .qwen:
            return "Qwen"
        case .kimi:
            return "Kimi"
        case .kiro:
            return "Kiro"
        case .muse:
            return "Muse"
        }
    }
}

enum AgentBlockedKind: String, CaseIterable, Equatable, Sendable {
    case input
    case question
    case permission
    case auth
}

enum AgentActivityPhase: Equatable, Sendable {
    case idle
    case running
    case needsInput(AgentBlockedKind)
    case done

    var isBlocked: Bool {
        if case .needsInput = self {
            return true
        }
        return false
    }
}

struct AgentSessionStatus: Equatable, Sendable {
    var agent: AgentKind
    var phase: AgentActivityPhase

    var isVisibleInTab: Bool {
        switch phase {
        case .running, .needsInput, .done:
            return true
        case .idle:
            return false
        }
    }

    var badgeLabel: String {
        switch phase {
        case .running:
            return "Running"
        case .needsInput(let kind):
            switch kind {
            case .permission:
                return "Approve"
            case .auth:
                return "Auth"
            case .question, .input:
                return "Input"
            }
        case .done:
            return "Done"
        case .idle:
            return "Idle"
        }
    }

    var helpText: String {
        switch phase {
        case .needsInput(let kind):
            let detail: String
            switch kind {
            case .question:
                detail = "Waiting for Answer"
            case .permission:
                detail = "Waiting for Approval"
            case .auth:
                detail = "Authentication Required"
            case .input:
                detail = "Waiting for Input"
            }
            return "\(agent.displayName) · \(detail)"
        case .running, .done, .idle:
            return "\(agent.displayName) · \(badgeLabel)"
        }
    }
}

struct AgentCommandMatch: Equatable, Sendable {
    var agent: AgentKind
    var startsWorkingImmediately: Bool
}

enum AgentCommandMatcher {
    private static let transparentWrappers: Set<String> = [
        "builtin", "command", "exec", "nohup", "time"
    ]

    private static let flagSkippingWrappers: Set<String> = [
        "arch", "caffeinate", "env", "nice", "sudo"
    ]

    private static let packageRunners: Set<String> = [
        "bunx", "dlx", "npx", "pnpx"
    ]

    private static let interpreters: Set<String> = [
        "bun", "deno", "node", "nodejs", "python", "python3", "ts-node", "tsx"
    ]

    private static let helpOrVersionFlags: Set<String> = [
        "-h", "--help", "-v", "-V", "--version"
    ]

    static func match(commandLine: String) -> AgentCommandMatch? {
        let segments = splitCommandSegments(commandLine)
        for segment in segments.reversed() {
            let tokens = tokenizeShellWords(segment)
            if let matched = matchTokens(tokens) {
                return matched
            }
        }
        return nil
    }

    static func match(executablePath: String, arguments: [String]) -> AgentCommandMatch? {
        if !arguments.isEmpty {
            var normalized = arguments
            if !executablePath.isEmpty {
                let execBase = basename(of: executablePath)
                let arg0Base = basename(of: arguments[0])
                if interpreters.contains(execBase), !interpreters.contains(arg0Base) {
                    if let direct = classifyTarget(arguments[0], remainingArguments: Array(arguments.dropFirst())) {
                        return direct
                    }
                    normalized.insert(executablePath, at: 0)
                }
            }
            if let matched = matchTokens(normalized) {
                return matched
            }
        }
        guard !executablePath.isEmpty else { return nil }
        return classifyTarget(executablePath, remainingArguments: [])
    }

    private static func matchTokens(_ rawTokens: [String]) -> AgentCommandMatch? {
        var index = 0
        let tokens = rawTokens

        while index < tokens.count {
            let token = tokens[index]
            if isEnvironmentAssignment(token) {
                index += 1
                continue
            }

            let base = basename(of: token)

            if transparentWrappers.contains(base) {
                index += 1
                continue
            }

            if flagSkippingWrappers.contains(base) {
                index = advancePastWrapperFlags(tokens: tokens, wrapper: base, from: index + 1)
                continue
            }

            if (base == "npm" || base == "pnpm" || base == "yarn"),
               index + 1 < tokens.count,
               tokens[index + 1] == "dlx" || tokens[index + 1] == "exec" {
                index = advancePastRunnerFlags(tokens: tokens, from: index + 2)
                continue
            }

            if base == "uv", index + 1 < tokens.count,
               tokens[index + 1] == "run" || tokens[index + 1] == "tool" {
                index += 2
                if index < tokens.count, tokens[index] == "run" {
                    index += 1
                }
                index = advancePastGenericLeadingFlags(tokens: tokens, from: index)
                continue
            }

            if packageRunners.contains(base) {
                index = advancePastRunnerFlags(tokens: tokens, from: index + 1)
                continue
            }

            if interpreters.contains(base) {
                guard let entrypointIndex = findInterpreterEntrypoint(
                    tokens: tokens,
                    interpreter: base,
                    from: index + 1
                ) else {
                    return nil
                }
                let target = tokens[entrypointIndex]
                let remaining = Array(tokens.dropFirst(entrypointIndex + 1))
                return classifyTarget(target, remainingArguments: remaining)
            }

            let remaining = Array(tokens.dropFirst(index + 1))
            return classifyTarget(token, remainingArguments: remaining)
        }

        return nil
    }

    private static func classifyTarget(
        _ target: String,
        remainingArguments: [String]
    ) -> AgentCommandMatch? {
        if remainingArguments.contains(where: { helpOrVersionFlags.contains($0) }) {
            return nil
        }

        guard let agent = identifyAgent(from: target) else {
            return nil
        }

        return AgentCommandMatch(
            agent: agent,
            startsWorkingImmediately: hasImmediateWorkFlag(for: agent, arguments: remainingArguments)
        )
    }

    static func identifyAgentName(_ rawName: String) -> AgentKind? {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let exact = AgentKind(rawValue: trimmed) {
            return exact
        }
        switch trimmed.lowercased() {
        case "claude", "claudecode", "claude-code", "claude_code":
            return .claudeCode
        case "droid", "factorydroid", "factory-droid", "factory_droid":
            return .factoryDroid
        case "antigravity", "agy", "antigravity-cli":
            return .agy
        case "gemini-cli":
            return .gemini
        case "github-copilot", "copilot-cli":
            return .copilot
        case "qwen-code":
            return .qwen
        case "muse-code":
            return .muse
        default:
            return identifyAgent(from: trimmed)
        }
    }

    private static func identifyAgent(from rawTarget: String) -> AgentKind? {
        let lowered = rawTarget.lowercased()
        let strippedSpecifier = stripVersionSuffix(from: lowered)
        let base = basename(of: strippedSpecifier)

        // 1. Exact binary / command name match
        switch base {
        case "claude", "claude-code":
            return .claudeCode
        case "codex", "codex-cli", "codex-aarch64-apple-darwin", "codex-x86_64-apple-darwin":
            return .codex
        case "pi", "pi-coding-agent":
            return .pi
        case "opencode", "opencode-ai", "opencode-darwin-arm64", "opencode-darwin-x64":
            return .opencode
        case "grok", "grok-cli":
            return .grok
        case "droid", "factory-droid":
            return .factoryDroid
        case "agy", "antigravity-cli":
            return .agy
        case "amp":
            return .amp
        case "gemini":
            return .gemini
        case "cursor-agent":
            return .cursor
        case "copilot":
            return .copilot
        case "qwen":
            return .qwen
        case "kimi", "kimi-cli":
            return .kimi
        case "kiro-cli", "kiro-cli-chat":
            return .kiro
        case "muse":
            return .muse
        default:
            break
        }

        // The `muse` launcher execs a versioned native binary such as `muse-bin-1.4.25-R9361.1`.
        if base.hasPrefix("muse-bin-") {
            return .muse
        }

        // 2. Package / installation path markers (e.g. node .../cli.js or npx @scope/pkg)
        if lowered.contains("@anthropic-ai/claude-code")
            || lowered.contains("/claude-code/")
            || lowered.contains("/.claude/local/") {
            return .claudeCode
        }
        if lowered.contains("@openai/codex")
            || lowered.contains("/codex-cli/")
            || lowered.contains("/@openai+codex") {
            return .codex
        }
        if lowered.contains("pi-coding-agent")
            || lowered.contains("@mariozechner/pi")
            || lowered.contains("@earendil-works/pi") {
            return .pi
        }
        if lowered.contains("/opencode-ai/")
            || lowered.contains("/opencode-darwin-")
            || lowered.contains("/.opencode/bin/")
            || lowered.contains("opencode-ai") {
            return .opencode
        }
        if lowered.contains("@xai-official/grok")
            || lowered.contains("@vibe-kit/grok-cli")
            || lowered.contains("/grok-cli/") {
            return .grok
        }
        if lowered.contains("@factory/droid")
            || lowered.contains("/.factory/bin/")
            || lowered.contains("/factory-droid/") {
            return .factoryDroid
        }
        if lowered.contains("/antigravity-cli/")
            || lowered.contains("@google/antigravity-cli") {
            return .agy
        }
        if lowered.contains("@sourcegraph/amp")
            || lowered.contains("@sourcegraph+amp")
            || lowered.contains("/.amp/bin/") {
            return .amp
        }
        if lowered.contains("@google/gemini-cli")
            || lowered.contains("@google+gemini-cli") {
            return .gemini
        }
        if lowered.contains("/cursor-agent/") {
            return .cursor
        }
        if lowered.contains("@github/copilot")
            || lowered.contains("@github+copilot") {
            return .copilot
        }
        if lowered.contains("@qwen-code/qwen-code")
            || lowered.contains("@qwen-code+qwen-code") {
            return .qwen
        }
        if lowered.contains("/kimi-cli/") {
            return .kimi
        }

        return nil
    }

    private static func hasImmediateWorkFlag(
        for agent: AgentKind,
        arguments: [String]
    ) -> Bool {
        guard !arguments.isEmpty else { return false }
        let firstPositional = firstPositionalSubcommand(in: arguments)

        switch agent {
        case .claudeCode:
            return arguments.contains("-p") || arguments.contains("--print")
        case .codex:
            return firstPositional == "exec" || firstPositional == "e"
                || arguments.contains("-q") || arguments.contains("--quiet")
        case .pi:
            return arguments.contains("-p") || arguments.contains("--print")
        case .opencode:
            return firstPositional == "run"
                || arguments.contains("-p") || arguments.contains("--prompt")
        case .grok:
            return arguments.contains("-p")
                || arguments.contains("--prompt")
                || arguments.contains("--print")
        case .factoryDroid:
            return firstPositional == "exec"
                || arguments.contains("-p") || arguments.contains("--prompt")
        case .agy:
            return firstPositional == "exec" || firstPositional == "run"
                || arguments.contains("-p")
                || arguments.contains("--prompt")
                || arguments.contains("--print")
        case .amp:
            return arguments.contains("-x") || arguments.contains("--execute")
        case .gemini, .copilot, .qwen:
            return arguments.contains("-p") || arguments.contains("--prompt")
        case .cursor:
            return arguments.contains("-p") || arguments.contains("--print")
        case .kimi:
            return arguments.contains("--print")
        case .kiro:
            return arguments.contains("--no-interactive")
        case .muse:
            return firstPositional == "exec"
        }
    }

    private static func firstPositionalSubcommand(in arguments: [String]) -> String? {
        let flagsTakingValue: Set<String> = [
            "-c", "--config", "--settings", "-m", "--model", "-p", "--profile",
            "-s", "--sandbox", "-a", "--ask-for-approval", "-C", "--cd",
            "--add-dir", "--agent", "--mode", "--effort", "--project",
            "--enable", "--disable"
        ]
        var index = 0
        while index < arguments.count {
            let token = arguments[index]
            if token == "--" {
                return index + 1 < arguments.count ? arguments[index + 1] : nil
            }
            if token.hasPrefix("-"), token.count > 1 {
                if !token.contains("="), flagsTakingValue.contains(token) {
                    index += 2
                } else {
                    index += 1
                }
                continue
            }
            return token
        }
        return nil
    }

    private static func advancePastWrapperFlags(
        tokens: [String],
        wrapper: String,
        from startIndex: Int
    ) -> Int {
        var index = startIndex
        while index < tokens.count {
            let token = tokens[index]
            if token == "--" {
                return index + 1
            }
            if wrapper == "env", isEnvironmentAssignment(token) {
                index += 1
                continue
            }
            guard token.hasPrefix("-"), token.count > 1 else {
                break
            }
            let flagsWithValue: Set<String> = ["-u", "-P", "-S", "-C", "-n", "-u", "-g"]
            if flagsWithValue.contains(token) {
                index += 2
            } else {
                index += 1
            }
        }
        return index
    }

    private static func advancePastRunnerFlags(tokens: [String], from startIndex: Int) -> Int {
        var index = startIndex
        while index < tokens.count {
            let token = tokens[index]
            if token == "--" {
                return index + 1
            }
            guard token.hasPrefix("-"), token.count > 1 else {
                break
            }
            if token == "-p" || token == "--package" || token == "-c" {
                // In `npx -p @openai/codex codex`, if -p itself names the package, keep scanning
                // to the command token unless -p is the final target.
                if index + 2 < tokens.count {
                    index += 2
                    continue
                }
            }
            index += 1
        }
        return index
    }

    private static func advancePastGenericLeadingFlags(tokens: [String], from startIndex: Int) -> Int {
        var index = startIndex
        while index < tokens.count {
            let token = tokens[index]
            if token == "--" {
                return index + 1
            }
            guard token.hasPrefix("-"), token.count > 1 else {
                break
            }
            index += 1
        }
        return index
    }

    private static func findInterpreterEntrypoint(
        tokens: [String],
        interpreter: String,
        from startIndex: Int
    ) -> Int? {
        var index = startIndex
        let flagsTakingNextArg: Set<String> = [
            "-r", "--require", "--import", "--loader", "--experimental-loader",
            "-C", "--conditions", "--watch-path", "--env-file"
        ]

        while index < tokens.count {
            let token = tokens[index]
            if token == "--" {
                return index + 1 < tokens.count ? index + 1 : nil
            }
            if (interpreter == "bun" || interpreter == "deno"),
               index == startIndex,
               token == "run" || token == "x" {
                index += 1
                continue
            }
            if (interpreter == "python" || interpreter == "python3"),
               token == "-m" {
                return index + 1 < tokens.count ? index + 1 : nil
            }
            if token == "-e" || token == "--eval" || token == "-p" || token == "--print" || token == "-c" {
                return nil
            }
            if token.hasPrefix("-") {
                if flagsTakingNextArg.contains(token) {
                    index += 2
                } else {
                    index += 1
                }
                continue
            }
            return index
        }
        return nil
    }

    private static func isEnvironmentAssignment(_ token: String) -> Bool {
        guard let equalsIndex = token.firstIndex(of: "="),
              equalsIndex != token.startIndex else {
            return false
        }
        let name = token[..<equalsIndex]
        guard let first = name.unicodeScalars.first,
              CharacterSet.letters.contains(first) || first == "_" else {
            return false
        }
        return name.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
        }
    }

    private static func basename(of path: String) -> String {
        guard !path.isEmpty else { return "" }
        if let slash = path.lastIndex(of: "/") {
            return String(path[path.index(after: slash)...])
        }
        return path
    }

    private static func stripVersionSuffix(from token: String) -> String {
        // Strip trailing `@version` from package specifiers like `@openai/codex@latest` or `opencode-ai@1.2.0`
        guard let atIndex = token.lastIndex(of: "@"), atIndex != token.startIndex else {
            return token
        }
        let prefix = token[..<atIndex]
        if prefix.hasSuffix("/") {
            return token
        }
        return String(prefix)
    }

    private static func splitCommandSegments(_ commandLine: String) -> [String] {
        var segments: [String] = []
        var current = ""
        var inSingleQuote = false
        var inDoubleQuote = false
        var isEscaped = false
        let chars = Array(commandLine)
        var i = 0

        while i < chars.count {
            let ch = chars[i]
            if isEscaped {
                current.append(ch)
                isEscaped = false
                i += 1
                continue
            }
            if ch == "\\" && !inSingleQuote {
                current.append(ch)
                isEscaped = true
                i += 1
                continue
            }
            if ch == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
                current.append(ch)
                i += 1
                continue
            }
            if ch == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
                current.append(ch)
                i += 1
                continue
            }
            if !inSingleQuote && !inDoubleQuote {
                if ch == ";" || ch == "\n" {
                    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { segments.append(trimmed) }
                    current = ""
                    i += 1
                    continue
                }
                if (ch == "&" || ch == "|"), i + 1 < chars.count, chars[i + 1] == ch {
                    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { segments.append(trimmed) }
                    current = ""
                    i += 2
                    continue
                }
            }
            current.append(ch)
            i += 1
        }

        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            segments.append(trimmed)
        }
        return segments
    }

    private static func tokenizeShellWords(_ segment: String) -> [String] {
        var words: [String] = []
        var current = ""
        var inSingleQuote = false
        var inDoubleQuote = false
        var isEscaped = false

        for ch in segment {
            if isEscaped {
                current.append(ch)
                isEscaped = false
                continue
            }
            if ch == "\\" && !inSingleQuote {
                isEscaped = true
                continue
            }
            if ch == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
                continue
            }
            if ch == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
                continue
            }
            if !inSingleQuote && !inDoubleQuote && ch.isWhitespace {
                if !current.isEmpty {
                    words.append(current)
                    current = ""
                }
                continue
            }
            current.append(ch)
        }

        if !current.isEmpty {
            words.append(current)
        }
        return words
    }
}

enum AgentTitleSpinnerDetector {
    private static let claudeSpinnerScalars: Set<UnicodeScalar> = [
        "✢", "✳", "✶", "✻", "✽"
    ]

    static func leadingSpinnerFrame(in title: String) -> UnicodeScalar? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.unicodeScalars.first else { return nil }
        // Braille patterns U+2801..U+28FF (excluding blank U+2800)
        if first.value >= 0x2801 && first.value <= 0x28FF {
            return first
        }
        if claudeSpinnerScalars.contains(first) {
            return first
        }
        return nil
    }
}

enum AgentStatusHintAction: Equatable, Sendable {
    case running
    case needsInput(AgentBlockedKind)
    case done
    case idle
}

struct ParsedAgentStatusHint: Equatable, Sendable {
    var action: AgentStatusHintAction
    var agent: AgentKind?
    var authoritative: Bool = false
}

enum AgentStatusHintParser {
    /// Parses both Rex's Program Status Protocol (`OSC 7501` key-value syntax, e.g.
    /// `state=blocked:kind=permission:app=claude-code`) and Colerm's shorthand hints
    /// (e.g. `running:claudeCode`, `blocked:question`, `permission`, `done`).
    static func parse(_ rawHint: String) -> ParsedAgentStatusHint? {
        let trimmed = rawHint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("=") {
            return parseKeyValueHint(trimmed)
        }
        return parsePositionalHint(trimmed)
    }

    private static func parseKeyValueHint(_ raw: String) -> ParsedAgentStatusHint? {
        var fields: [String: String] = [:]
        for pair in raw.split(whereSeparator: { $0 == ":" || $0 == ";" }) {
            guard let eq = pair.firstIndex(of: "=") else { continue }
            let key = pair[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            let value = pair[pair.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                fields[key] = value
            }
        }

        guard let rawState = fields["state"]?.lowercased(), !rawState.isEmpty else {
            return nil
        }

        let agent = (fields["app"] ?? fields["agent"]).flatMap(AgentCommandMatcher.identifyAgentName)
        let rawAuth = (fields["auth"] ?? fields["authoritative"])?.lowercased()
        let authoritative = rawAuth == "1" || rawAuth == "true" || rawAuth == "yes"
        let action: AgentStatusHintAction
        switch rawState {
        case "working", "running", "start":
            action = .running
        case "blocked", "waiting", "needs_input", "input":
            let blockedKind = fields["kind"].flatMap(parseBlockedKind) ?? .input
            action = .needsInput(blockedKind)
        case "done", "finished", "stop", "error", "fail", "failed":
            action = .done
        case "idle", "clear":
            action = .idle
        default:
            return nil
        }

        return ParsedAgentStatusHint(
            action: action,
            agent: agent,
            authoritative: authoritative
        )
    }

    private static func parsePositionalHint(_ raw: String) -> ParsedAgentStatusHint? {
        let parts = raw
            .split(separator: ":", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = parts.first?.lowercased(), !first.isEmpty else {
            return nil
        }

        switch first {
        case "running", "working", "start":
            let agent = parts.count > 1 ? AgentCommandMatcher.identifyAgentName(parts[1]) : nil
            return ParsedAgentStatusHint(action: .running, agent: agent)

        case "done", "stop", "finished":
            let agent = parts.count > 1 ? AgentCommandMatcher.identifyAgentName(parts[1]) : nil
            return ParsedAgentStatusHint(action: .done, agent: agent)

        case "idle", "clear":
            let agent = parts.count > 1 ? AgentCommandMatcher.identifyAgentName(parts[1]) : nil
            return ParsedAgentStatusHint(action: .idle, agent: agent)

        case "question", "permission", "approval", "approve", "auth":
            let kind = parseBlockedKind(first) ?? .input
            let agent = parts.count > 1 ? AgentCommandMatcher.identifyAgentName(parts[1]) : nil
            return ParsedAgentStatusHint(action: .needsInput(kind), agent: agent)

        case "blocked", "waiting", "needs_input", "input":
            if parts.count > 1, let subKind = parseBlockedKind(parts[1]) {
                let agent = parts.count > 2 ? AgentCommandMatcher.identifyAgentName(parts[2]) : nil
                return ParsedAgentStatusHint(action: .needsInput(subKind), agent: agent)
            }
            let agent = parts.count > 1 ? AgentCommandMatcher.identifyAgentName(parts[1]) : nil
            return ParsedAgentStatusHint(action: .needsInput(.input), agent: agent)

        default:
            return nil
        }
    }

    private static func parseBlockedKind(_ raw: String) -> AgentBlockedKind? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "question", "ask":
            return .question
        case "permission", "approval", "approve":
            return .permission
        case "auth", "login":
            return .auth
        case "input", "blocked", "waiting":
            return .input
        default:
            return nil
        }
    }
}

enum AgentViewportAnalyzer {
    private static let busyPhrases: [String] = [
        "esc to interrupt",
        "esc to cancel",
        "esc interrupt",
        "ctrl+c to interrupt",
        "ctrl+c to cancel"
    ]

    private static let idleComposerMarkers: [String] = [
        "? for shortcuts",
        "shift+tab to cycle",
        "shift+tab agents",
        "ask codex to do anything",
        "ask anything..."
    ]

    private static let permissionHeaderPhrases: [String] = [
        "do you want to proceed",
        "do you want to allow",
        "do you want to make this edit",
        "do you want to create",
        "do you want to delete",
        "do you want to run",
        "do you trust the files in this folder",
        "would you like to run",
        "would you like to apply",
        "allow execution of",
        "allow command?",
        "approve command?",
        "approve this command",
        "waiting for user confirmation",
        "requires approval"
    ]

    private static let permissionChoicePhrases: [String] = [
        "yes, allow",
        "allow once",
        "always allow",
        "allow for this session",
        "yes, proceed",
        "yes, and don't ask again",
        "don't ask again"
    ]

    private static let authPromptPhrases: [String] = [
        "select login method",
        "waiting for authentication",
        "paste your api key",
        "enter your api key",
        "open this url in your browser to authenticate",
        "sign in to continue"
    ]

    private static let yesNoSuffixes: [String] = [
        "[y/n]", "(y/n)", "[y/n/a]", "(y/n/a)", "[yes/no]", "(yes/no)"
    ]

    private static let taskRowLeadingGlyphs: Set<UnicodeScalar> = [
        "●", "○", "◉", "◐", "◑", "◒", "◓"
    ]

    static func hasActiveBackgroundTaskIndicator(in tailLines: [String]) -> Bool {
        if detectedBlockedKind(in: tailLines) != nil {
            return false
        }
        let meaningful = nonSeparatorTailLines(from: tailLines)
        guard !meaningful.isEmpty else { return false }

        // AGY status bar summary when background tasks are running, e.g.:
        // `? for shortcuts   auto · Gemini 4 Carbon · high · 1 task(s) · /tasks`
        for line in meaningful.suffix(2) {
            if containsActiveTaskCountSummary(line.lowercased()) {
                return true
            }
        }

        // AGY background task shelf rows pinned below the composer, e.g.:
        // `● [18:40:02] set -euo pipefail echo "=== 1. Clean & Deb... running`
        for line in meaningful.suffix(5) {
            if isActiveBackgroundTaskRow(line) {
                return true
            }
        }

        return false
    }

    static func hasExplicitBusyIndicator(in tailLines: [String]) -> Bool {
        if detectedBlockedKind(in: tailLines) != nil {
            return false
        }
        if hasActiveBackgroundTaskIndicator(in: tailLines) {
            return true
        }
        if hasIdleComposerFooter(in: tailLines) {
            return false
        }
        for line in nonSeparatorTailLines(from: tailLines).suffix(6) {
            let lowered = line.lowercased()
            if busyPhrases.contains(where: { lowered.contains($0) }) {
                return true
            }
        }
        return false
    }

    static func hasIdleComposerFooter(in tailLines: [String]) -> Bool {
        if hasActiveBackgroundTaskIndicator(in: tailLines) {
            return false
        }
        let footerLines = nonSeparatorTailLines(from: tailLines).suffix(4).map { $0.lowercased() }
        guard !footerLines.isEmpty else { return false }
        if hasInteractivePromptFooter(in: footerLines) {
            return false
        }
        return footerLines.contains { line in
            idleComposerMarkers.contains(where: { line.contains($0) })
        }
    }

    static func detectedBlockedKind(in tailLines: [String]) -> AgentBlockedKind? {
        guard !tailLines.isEmpty else { return nil }
        let loweredLines = tailLines.suffix(12).map { $0.lowercased() }
        let footerLines = Array(loweredLines.suffix(4))
        let bottomTwoLines = Array(loweredLines.suffix(2))

        let hasPromptFooter = hasInteractivePromptFooter(in: footerLines)
        if !hasPromptFooter,
           footerLines.contains(where: { line in idleComposerMarkers.contains(where: { line.contains($0) }) }) {
            return nil
        }

        let recentDialogLines = Array(loweredLines.suffix(8))
        let numberedChoiceCount = recentDialogLines.filter(isNumberedChoiceLine).count
        let hasPermissionChoice = recentDialogLines.contains { line in
            permissionChoicePhrases.contains(where: { line.contains($0) })
        }

        // 1. Permission / approval prompts (checked before generic selector legends so
        //    permission menus with `↑/↓ to navigate` still classify as `.permission`).
        let hasPermissionHeader = loweredLines.contains { line in
            permissionHeaderPhrases.contains(where: { line.contains($0) })
        }
        if hasPermissionHeader && (hasPromptFooter || numberedChoiceCount >= 2 || hasPermissionChoice) {
            return .permission
        }

        if hasPermissionChoice && (hasPromptFooter || numberedChoiceCount >= 2) {
            return .permission
        }

        if bottomTwoLines.contains(where: hasTrailingYesNoPrompt) {
            return .permission
        }

        // 2. Authentication / login prompts
        if loweredLines.suffix(6).contains(where: { line in
            authPromptPhrases.contains(where: { line.contains($0) })
        }) {
            return .auth
        }

        // 3. Interactive question / choice menus (AGY, Claude Code, Codex, OpenCode, Pi)
        if footerLines.contains(where: isNavigationSelectionLegend) {
            return .question
        }

        if loweredLines.contains(where: containsNumberedQuestionHeader),
           (hasPromptFooter || numberedChoiceCount >= 2) {
            return .question
        }

        return nil
    }

    private static func hasInteractivePromptFooter(in footerLines: [String]) -> Bool {
        footerLines.contains { line in
            line.contains("esc to cancel")
                || line.contains("esc skip")
                || line.contains("press enter to confirm")
                || line.contains("enter to select")
                || isNavigationSelectionLegend(line)
        }
    }

    private static func isNavigationSelectionLegend(_ line: String) -> Bool {
        let hasNavigation = line.contains("navigate")
            || line.contains("↑/↓")
            || line.contains("↑↓")
            || line.contains("arrow keys")
            || line.contains("up/down")
        let hasSelection = line.contains("enter select")
            || line.contains("enter to select")
            || line.contains("enter confirm")
            || line.contains("enter to confirm")
            || line.contains("enter to submit")
        return hasNavigation && hasSelection
    }

    private static func containsNumberedQuestionHeader(_ line: String) -> Bool {
        guard let range = line.range(of: "question ") else { return false }
        var rest = line[range.upperBound...]
        let firstDigits = rest.prefix(while: { $0.isNumber && $0.isASCII })
        guard !firstDigits.isEmpty else { return false }
        rest = rest.dropFirst(firstDigits.count)
        guard rest.first == "/" else { return false }
        rest = rest.dropFirst()
        let secondDigits = rest.prefix(while: { $0.isNumber && $0.isASCII })
        return !secondDigits.isEmpty
    }

    private static func isNumberedChoiceLine(_ line: String) -> Bool {
        let trimmed = line.drop { ch in
            ch.isWhitespace || ch == ">" || ch == "❯" || ch == "›" || ch == "•" || ch == "*" || ch == "→"
        }
        guard let first = trimmed.first, first.isASCII, first.isNumber, first != "0" else {
            return false
        }
        let afterDigits = trimmed.drop(while: { $0.isASCII && $0.isNumber })
        return afterDigits.hasPrefix(". ") || afterDigits.hasPrefix(") ")
    }

    private static func hasTrailingYesNoPrompt(_ line: String) -> Bool {
        var trimmed = Substring(line)
        while let last = trimmed.last,
              last.isWhitespace || last == "?" || last == ":" || last == ">" || last == "›" {
            trimmed = trimmed.dropLast()
        }
        let candidate = String(trimmed)
        return yesNoSuffixes.contains(where: { candidate.hasSuffix($0) })
    }

    private static func nonSeparatorTailLines(from tailLines: [String]) -> [String] {
        tailLines.filter { !isBoxDrawingSeparatorLine($0) }
    }

    private static func isBoxDrawingSeparatorLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return trimmed.unicodeScalars.allSatisfy { scalar in
            if scalar.value >= 0x2500 && scalar.value <= 0x257F {
                return true
            }
            return scalar == "-" || scalar == "=" || scalar == "_"
        }
    }

    private static func containsActiveTaskCountSummary(_ loweredLine: String) -> Bool {
        guard loweredLine.contains("/tasks") else { return false }
        var searchStart = loweredLine.startIndex
        while let range = loweredLine.range(of: " task(s)", range: searchStart..<loweredLine.endIndex) {
            var digitStart = range.lowerBound
            while digitStart > loweredLine.startIndex {
                let prev = loweredLine.index(before: digitStart)
                let ch = loweredLine[prev]
                if ch.isASCII && ch.isNumber {
                    digitStart = prev
                } else {
                    break
                }
            }
            if digitStart < range.lowerBound,
               let count = Int(loweredLine[digitStart..<range.lowerBound]),
               count > 0 {
                return true
            }
            searchStart = range.upperBound
        }
        return false
    }

    private static func isActiveBackgroundTaskRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.unicodeScalars.first else { return false }
        let isLeadingStatusGlyph = taskRowLeadingGlyphs.contains(first)
            || (first.value >= 0x2801 && first.value <= 0x28FF)
        guard isLeadingStatusGlyph else { return false }
        guard trimmed.lowercased().hasSuffix(" running") else { return false }

        let afterGlyph = trimmed[trimmed.index(after: trimmed.startIndex)...]
            .drop(while: { $0 == " " || $0 == "\t" })
        return hasLeadingBracketedTimestamp(afterGlyph)
    }

    private static func hasLeadingBracketedTimestamp(_ text: Substring) -> Bool {
        // Matches `[HH:MM:SS]`
        let chars = Array(text.prefix(10))
        guard chars.count == 10,
              chars[0] == "[",
              chars[3] == ":",
              chars[6] == ":",
              chars[9] == "]"
        else {
            return false
        }
        return [1, 2, 4, 5, 7, 8].allSatisfy { chars[$0].isASCII && chars[$0].isNumber }
    }
}

struct AgentChildProcessObservation: Equatable, Sendable {
    var pid: pid_t
    var totalCPUNanoseconds: UInt64
    var isHelperDaemon: Bool = false
}

struct AgentProcessObservation: Equatable, Sendable {
    var agent: AgentKind
    var rootPID: pid_t
    var startsWorkingImmediately: Bool
    var totalCPUNanoseconds: UInt64
    var nonAgentChildren: [AgentChildProcessObservation]
}

struct AgentActivityTracker {
    static let startupBootWindow: TimeInterval = 6.0
    static let passiveSettleInterval: TimeInterval = 2.0
    static let hintedSettleInterval: TimeInterval = 0.6
    static let blockedSettleInterval: TimeInterval = 0.5
    static let interactionCooldownInterval: TimeInterval = 1.2
    static let unconfirmedEmptySubmitTimeout: TimeInterval = 1.5
    static let unconfirmedPromptSubmitTimeout: TimeInterval = 3.0
    static let transientToolSilenceLimit: TimeInterval = 8.0
    static let recentHistoryCapacity = 6
    static let heavyAgentCPUNanosThreshold: UInt64 = 40_000_000 // ~8% of one core over 0.5s
    static let heavyChildCPUNanosThreshold: UInt64 = 80_000_000 // ~16% of one core over 0.5s

    private(set) var status: AgentSessionStatus?

    private var activeRootPID: pid_t?
    private var isAgentProcessAlive = false
    private var isHeadlessRun = false
    private var isExplicitlyBlocked = false
    private var hasAuthoritativeHooks = false
    private var interruptedWhileAuthoritative = false
    private var agentDetectedAt: TimeInterval = 0
    private var lastWorkSignalAt: TimeInterval = 0
    private var lastNovelScreenOrStartAt: TimeInterval = 0
    private var lastCompletionHintAt: TimeInterval?
    private var lastUserTypingAt: TimeInterval?
    private var lastUserSubmitAt: TimeInterval?
    private var lastUserInteractionAt: TimeInterval?
    private var lastInterruptAt: TimeInterval?
    private var hadTypedInputBeforeSubmit = false
    private var pollsSinceSubmit = 0

    private var turnConfirmed = false
    private var consecutiveWorkTicks = 0

    private var recentViewportHashes: [UInt64] = []
    private var hasInitializedViewport = false
    private var lastObservedViewportHash: UInt64?
    private var dismissedBlockedViewportHash: UInt64?

    private var previousTotalCPUNanos: UInt64?
    private var childFirstSeenAt: [pid_t: TimeInterval] = [:]
    private var childLastActiveAt: [pid_t: TimeInterval] = [:]
    private var childPreviousCPUNanos: [pid_t: UInt64] = [:]
    private var baselineChildPIDs: Set<pid_t> = []
    private var lastPollHadActiveToolChild = false
    private var lastPollHadActiveBackgroundTask = false

    private var lastTitle: String?
    private var lastSpinnerFrame: UnicodeScalar?
    private var lastSpinnerAnimationAt: TimeInterval?
    private var spinnerFrameTransitions = 0

    private var isProgressActive = false

    @discardableResult
    mutating func commandStarted(
        commandLine: String?,
        isTabSelected _: Bool,
        now: TimeInterval
    ) -> Bool {
        let previous = status

        guard let commandLine, !commandLine.isEmpty else {
            return false
        }

        if let match = AgentCommandMatcher.match(commandLine: commandLine) {
            beginTrackingAgent(
                match.agent,
                rootPID: nil,
                startsWorkingImmediately: match.startsWorkingImmediately,
                now: now
            )
        } else {
            resetAll()
        }

        return status != previous
    }

    @discardableResult
    mutating func commandFinished(
        exitCode: Int32?,
        isTabSelected: Bool,
        now _: TimeInterval
    ) -> Bool {
        let previous = status
        guard let current = status else {
            resetLiveMetrics()
            return false
        }

        let wasInterrupted = exitCode == 130
        if current.phase == .running, (turnConfirmed || isHeadlessRun), !wasInterrupted, !isTabSelected {
            status = AgentSessionStatus(agent: current.agent, phase: .done)
            isAgentProcessAlive = false
            isHeadlessRun = false
            isExplicitlyBlocked = false
            hasAuthoritativeHooks = false
            interruptedWhileAuthoritative = false
            resetLiveMetrics()
        } else if current.phase == .done, !isTabSelected {
            isAgentProcessAlive = false
            isHeadlessRun = false
            isExplicitlyBlocked = false
            hasAuthoritativeHooks = false
            interruptedWhileAuthoritative = false
            resetLiveMetrics()
        } else {
            resetAll()
        }

        return status != previous
    }

    @discardableResult
    mutating func handleUserInput(
        _ kind: TerminalUserInputKind,
        now: TimeInterval
    ) -> Bool {
        let previous = status
        switch kind {
        case .typing:
            lastUserTypingAt = now

        case .interaction:
            lastUserInteractionAt = now

        case .interrupt:
            lastUserTypingAt = nil
            lastCompletionHintAt = now
            lastInterruptAt = now
            if let current = status {
                if current.phase.isBlocked {
                    isExplicitlyBlocked = false
                    interruptedWhileAuthoritative = false
                    dismissedBlockedViewportHash = lastObservedViewportHash
                    turnConfirmed = false
                    hadTypedInputBeforeSubmit = false
                    consecutiveWorkTicks = 0
                    status = isAgentProcessAlive
                        ? AgentSessionStatus(agent: current.agent, phase: .idle)
                        : nil
                } else if current.phase == .running {
                    if hasAuthoritativeHooks {
                        interruptedWhileAuthoritative = true
                    } else if !turnConfirmed {
                        status = AgentSessionStatus(agent: current.agent, phase: .idle)
                        hadTypedInputBeforeSubmit = false
                    }
                }
            }

        case .submit:
            let typedRecently = lastUserTypingAt.map { (now - $0) <= 30.0 } ?? false
            lastUserSubmitAt = now
            lastUserTypingAt = nil
            pollsSinceSubmit = 0
            guard let current = status, isAgentProcessAlive else {
                break
            }
            let wasAnsweringBlockedPrompt = current.phase.isBlocked
            isExplicitlyBlocked = false
            dismissedBlockedViewportHash = nil
            if hasAuthoritativeHooks {
                // In authoritative hook mode, `UserPromptSubmit` drives idle -> running so empty
                // Return or slash menus never flash Running. When answering a blocked prompt
                // (e.g. approving a slow Bash tool), transition immediately to Running until
                // PostToolUse / Stop arrives.
                if wasAnsweringBlockedPrompt {
                    interruptedWhileAuthoritative = false
                    status = AgentSessionStatus(agent: current.agent, phase: .running)
                    turnConfirmed = true
                    consecutiveWorkTicks = 0
                    lastWorkSignalAt = now
                    lastNovelScreenOrStartAt = now
                    lastCompletionHintAt = nil
                }
                break
            }
            if current.phase != .running {
                status = AgentSessionStatus(agent: current.agent, phase: .running)
                turnConfirmed = false
                hadTypedInputBeforeSubmit = typedRecently || wasAnsweringBlockedPrompt
                consecutiveWorkTicks = 0
                lastWorkSignalAt = now
                lastNovelScreenOrStartAt = now
                lastCompletionHintAt = nil
            } else {
                if typedRecently {
                    hadTypedInputBeforeSubmit = true
                }
                lastWorkSignalAt = now
                lastNovelScreenOrStartAt = now
            }
        }
        return status != previous
    }

    @discardableResult
    mutating func handleTitleChange(
        _ title: String,
        isTabSelected: Bool,
        now: TimeInterval
    ) -> Bool {
        guard title != lastTitle else { return false }
        let previous = status
        lastTitle = title

        if hasAuthoritativeHooks {
            return false
        }

        let newFrame = AgentTitleSpinnerDetector.leadingSpinnerFrame(in: title)
        let hadPreviousSpinner = lastSpinnerFrame != nil
        let inBootWindow = (now - agentDetectedAt) < Self.startupBootWindow

        if let newFrame {
            if let oldFrame = lastSpinnerFrame, oldFrame != newFrame {
                spinnerFrameTransitions += 1
                lastSpinnerAnimationAt = now
                if let current = status,
                   isAgentProcessAlive,
                   spinnerFrameTransitions >= 2,
                   (!inBootWindow || current.phase == .running || current.phase.isBlocked) {
                    isExplicitlyBlocked = false
                    status = AgentSessionStatus(agent: current.agent, phase: .running)
                    turnConfirmed = true
                    lastWorkSignalAt = now
                    lastNovelScreenOrStartAt = now
                    lastCompletionHintAt = nil
                }
            }
            lastSpinnerFrame = newFrame
        } else {
            if hadPreviousSpinner, spinnerFrameTransitions > 0 {
                lastCompletionHintAt = now
                if let current = status,
                   current.phase == .running,
                   turnConfirmed,
                   !isHeadlessRun,
                   !isProgressActive,
                   now - lastWorkSignalAt >= Self.hintedSettleInterval {
                    completeRunningTurn(for: current.agent, isTabSelected: isTabSelected)
                }
            }
            lastSpinnerFrame = nil
            spinnerFrameTransitions = 0
        }

        return status != previous
    }

    @discardableResult
    mutating func handleProgressReport(
        _ progress: GhosttyProgressState,
        isTabSelected: Bool,
        now: TimeInterval
    ) -> Bool {
        if hasAuthoritativeHooks {
            isProgressActive = (progress == .active)
            return false
        }
        let previous = status
        let inBootWindow = (now - agentDetectedAt) < Self.startupBootWindow

        switch progress {
        case .active:
            if let current = status,
               isAgentProcessAlive,
               (!inBootWindow || current.phase == .running || current.phase.isBlocked) {
                isProgressActive = true
                isExplicitlyBlocked = false
                status = AgentSessionStatus(agent: current.agent, phase: .running)
                turnConfirmed = true
                lastWorkSignalAt = now
                lastNovelScreenOrStartAt = now
                lastCompletionHintAt = nil
            }
        case .remove, .error:
            let wasActive = isProgressActive
            isProgressActive = false
            if wasActive {
                lastCompletionHintAt = now
                if let current = status,
                   current.phase == .running,
                   turnConfirmed,
                   !isHeadlessRun,
                   !lastPollHadActiveToolChild,
                   !lastPollHadActiveBackgroundTask,
                   now - lastWorkSignalAt >= Self.hintedSettleInterval {
                    completeRunningTurn(for: current.agent, isTabSelected: isTabSelected)
                }
            }
        case .pause:
            isProgressActive = false
        }
        return status != previous
    }

    @discardableResult
    mutating func handleCompletionNotificationHint(now: TimeInterval) -> Bool {
        guard status != nil else { return false }
        lastCompletionHintAt = now
        return false
    }

    @discardableResult
    mutating func handleDesktopNotification(
        title: String,
        body: String,
        now: TimeInterval
    ) -> Bool {
        guard let current = status, isAgentProcessAlive else { return false }
        let previous = status
        let combined = "\(title) \(body)".lowercased()

        let inferredBlockedKind: AgentBlockedKind?
        if combined.contains("permission")
            || combined.contains("approval")
            || combined.contains("approve")
            || combined.contains("allow ") {
            inferredBlockedKind = .permission
        } else if combined.contains("authentication")
            || combined.contains("sign in")
            || combined.contains("log in")
            || combined.contains("api key") {
            inferredBlockedKind = .auth
        } else if combined.contains("question")
            || combined.contains("waiting for your answer") {
            inferredBlockedKind = .question
        } else if combined.contains("waiting for your input")
            || combined.contains("waiting for input")
            || combined.contains("needs your input")
            || combined.contains("needs input")
            || combined.contains("input required")
            || combined.contains("action required") {
            inferredBlockedKind = .input
        } else {
            inferredBlockedKind = nil
        }

        if let kind = inferredBlockedKind {
            isExplicitlyBlocked = true
            dismissedBlockedViewportHash = nil
            turnConfirmed = false
            consecutiveWorkTicks = 0
            lastCompletionHintAt = nil
            status = AgentSessionStatus(agent: current.agent, phase: .needsInput(kind))
        } else {
            lastCompletionHintAt = now
        }

        return status != previous
    }

    @discardableResult
    mutating func handleExplicitHint(
        _ rawHint: String,
        fallbackAgent: AgentKind? = nil,
        isTabSelected: Bool,
        now: TimeInterval
    ) -> Bool {
        let previous = status
        guard let parsed = AgentStatusHintParser.parse(rawHint),
              let agent = parsed.agent ?? status?.agent ?? fallbackAgent
        else {
            return false
        }

        if parsed.authoritative {
            hasAuthoritativeHooks = true
            interruptedWhileAuthoritative = false
        }

        switch parsed.action {
        case .running:
            isAgentProcessAlive = true
            isExplicitlyBlocked = false
            dismissedBlockedViewportHash = nil
            status = AgentSessionStatus(agent: agent, phase: .running)
            turnConfirmed = true
            lastWorkSignalAt = now
            lastNovelScreenOrStartAt = now
            lastCompletionHintAt = nil

        case .needsInput(let kind):
            isAgentProcessAlive = true
            isExplicitlyBlocked = true
            dismissedBlockedViewportHash = nil
            status = AgentSessionStatus(agent: agent, phase: .needsInput(kind))
            turnConfirmed = false
            consecutiveWorkTicks = 0
            lastCompletionHintAt = nil

        case .done:
            isExplicitlyBlocked = false
            completeRunningTurn(for: agent, isTabSelected: isTabSelected)

        case .idle:
            isExplicitlyBlocked = false
            status = isAgentProcessAlive ? AgentSessionStatus(agent: agent, phase: .idle) : nil
            if !isAgentProcessAlive {
                hasAuthoritativeHooks = false
            }
            turnConfirmed = false
            consecutiveWorkTicks = 0
        }
        return status != previous
    }

    @discardableResult
    mutating func clearCompletedStatus() -> Bool {
        guard let current = status, current.phase == .done else {
            return false
        }
        if isAgentProcessAlive {
            status = AgentSessionStatus(agent: current.agent, phase: .idle)
        } else {
            resetAll()
        }
        return true
    }

    @discardableResult
    mutating func poll(
        observation: AgentProcessObservation?,
        viewport: TerminalViewportSnapshot? = nil,
        canObserveProcesses: Bool = true,
        isTabSelected: Bool,
        now: TimeInterval
    ) -> Bool {
        let previous = status

        if observation == nil {
            if canObserveProcesses {
                handleAbsentAgentProcess(isTabSelected: isTabSelected)
            }
            return status != previous
        }

        guard let observation else { return false }

        let isNewProcess = !isAgentProcessAlive
            || status?.agent != observation.agent
            || (activeRootPID != nil && activeRootPID != observation.rootPID)

        if isNewProcess {
            let preserveAuthoritativeHooks = status?.agent == observation.agent
                && activeRootPID == nil
                && hasAuthoritativeHooks
            let preserveRunningFromPreexec = status?.agent == observation.agent
                && activeRootPID == nil
                && status?.phase == .running
            let preservedBlockedPhase: AgentActivityPhase? = {
                guard status?.agent == observation.agent,
                      activeRootPID == nil,
                      isExplicitlyBlocked,
                      let phase = status?.phase,
                      phase.isBlocked
                else {
                    return nil
                }
                return phase
            }()
            beginTrackingAgent(
                observation.agent,
                rootPID: observation.rootPID,
                startsWorkingImmediately: observation.startsWorkingImmediately || (preserveRunningFromPreexec && isHeadlessRun),
                now: now
            )
            if preserveAuthoritativeHooks {
                hasAuthoritativeHooks = true
            }
            if let preservedBlockedPhase {
                isExplicitlyBlocked = true
                status = AgentSessionStatus(agent: observation.agent, phase: preservedBlockedPhase)
            } else if preserveRunningFromPreexec && !isHeadlessRun {
                status = AgentSessionStatus(agent: observation.agent, phase: .running)
            }
            previousTotalCPUNanos = observation.totalCPUNanoseconds
            for child in observation.nonAgentChildren {
                baselineChildPIDs.insert(child.pid)
                childFirstSeenAt[child.pid] = now
                childLastActiveAt[child.pid] = now
                childPreviousCPUNanos[child.pid] = child.totalCPUNanoseconds
            }
            if let viewport {
                lastObservedViewportHash = viewport.contentHash
                recordViewportHash(viewport.contentHash)
                hasInitializedViewport = true
                let hasActiveBackgroundTask = AgentViewportAnalyzer.hasActiveBackgroundTaskIndicator(
                    in: viewport.tailLines
                )
                lastPollHadActiveBackgroundTask = hasActiveBackgroundTask
                if hasActiveBackgroundTask, status?.phase == .idle {
                    status = AgentSessionStatus(agent: observation.agent, phase: .running)
                    turnConfirmed = true
                    lastWorkSignalAt = now
                }
            }
            return status != previous
        }

        if activeRootPID == nil {
            activeRootPID = observation.rootPID
        }

        // Headless one-shot runs (`claude -p`, `droid exec`, `codex exec`, `opencode run`)
        // stay `.running` until the process exits.
        if isHeadlessRun {
            lastWorkSignalAt = now
            return status != previous
        }

        let inBootWindow = (now - agentDetectedAt) < Self.startupBootWindow
        let isRecentTypingWindow = lastUserTypingAt.map { (now - $0) < 0.7 } ?? false
        let isRecentInteractionWindow = lastUserInteractionAt.map { (now - $0) < Self.interactionCooldownInterval } ?? false
        let suppressViewportDiff = isRecentTypingWindow || isRecentInteractionWindow
        let hasUnsubmittedTyping = lastUserTypingAt.map { typingAt in
            (lastUserSubmitAt ?? 0) < typingAt && (now - typingAt) < 10.0
        } ?? false
        if lastUserSubmitAt != nil {
            pollsSinceSubmit += 1
        }

        // 1. Evaluate active-screen text changes & interactive prompts (immune to cursor blink & scrollback)
        var autonomousNovelViewportChange = false
        var hasActiveBackgroundTask = false
        var hasExplicitBusyBanner = false
        var detectedBlockedKind: AgentBlockedKind?
        var hasIdleComposerFooter = false
        if let viewport {
            lastObservedViewportHash = viewport.contentHash
            if dismissedBlockedViewportHash != nil, viewport.contentHash != dismissedBlockedViewportHash {
                dismissedBlockedViewportHash = nil
            }
            if viewport.contentHash != dismissedBlockedViewportHash {
                detectedBlockedKind = AgentViewportAnalyzer.detectedBlockedKind(in: viewport.tailLines)
            }
            hasActiveBackgroundTask = (detectedBlockedKind == nil)
                && AgentViewportAnalyzer.hasActiveBackgroundTaskIndicator(in: viewport.tailLines)
            hasIdleComposerFooter = AgentViewportAnalyzer.hasIdleComposerFooter(in: viewport.tailLines)
            hasExplicitBusyBanner = (detectedBlockedKind == nil)
                && AgentViewportAnalyzer.hasExplicitBusyIndicator(in: viewport.tailLines)
            let isNovel = hasInitializedViewport && !recentViewportHashes.contains(viewport.contentHash)
            recordViewportHash(viewport.contentHash)
            hasInitializedViewport = true

            let ignoreEmptySubmitEcho = !hadTypedInputBeforeSubmit
                && (lastUserSubmitAt != nil)
                && (pollsSinceSubmit == 1)
            if isNovel && !suppressViewportDiff && (!ignoreEmptySubmitEcho || hasExplicitBusyBanner || detectedBlockedKind != nil) {
                autonomousNovelViewportChange = true
                lastNovelScreenOrStartAt = now
            }
        }

        // 2. Evaluate CPU delta across agent tree (used only as fallback when viewport is unavailable)
        var cpuDelta: UInt64 = 0
        if let prevCPU = previousTotalCPUNanos, observation.totalCPUNanoseconds >= prevCPU {
            cpuDelta = observation.totalCPUNanoseconds - prevCPU
        }
        previousTotalCPUNanos = observation.totalCPUNanoseconds
        let hasHeavyAgentCPU = cpuDelta >= Self.heavyAgentCPUNanosThreshold

        // 3. Evaluate transient tool subprocesses (ignoring startup/MCP/LSP/sidecar helpers)
        let activeChildIDs = Set(observation.nonAgentChildren.map(\.pid))
        childFirstSeenAt = childFirstSeenAt.filter { activeChildIDs.contains($0.key) }
        childLastActiveAt = childLastActiveAt.filter { activeChildIDs.contains($0.key) }
        childPreviousCPUNanos = childPreviousCPUNanos.filter { activeChildIDs.contains($0.key) }
        baselineChildPIDs = baselineChildPIDs.intersection(activeChildIDs)

        let turnFloor = lastUserSubmitAt ?? agentDetectedAt
        let hasActiveViewportWork = hasExplicitBusyBanner || hasActiveBackgroundTask
        var hasActiveTransientToolChild = false
        for child in observation.nonAgentChildren {
            let firstSeen = childFirstSeenAt[child.pid] ?? now
            if childFirstSeenAt[child.pid] == nil {
                childFirstSeenAt[child.pid] = now
                childLastActiveAt[child.pid] = now
                if inBootWindow || child.isHelperDaemon || firstSeen < turnFloor {
                    baselineChildPIDs.insert(child.pid)
                }
            }

            let prevChildCPU = childPreviousCPUNanos[child.pid] ?? child.totalCPUNanoseconds
            let childCPUDelta = child.totalCPUNanoseconds >= prevChildCPU
                ? (child.totalCPUNanoseconds - prevChildCPU)
                : 0
            childPreviousCPUNanos[child.pid] = child.totalCPUNanoseconds

            if !child.isHelperDaemon, childCPUDelta >= Self.heavyChildCPUNanosThreshold {
                childLastActiveAt[child.pid] = now
                hasActiveTransientToolChild = true
            } else if !baselineChildPIDs.contains(child.pid) {
                if hasActiveViewportWork {
                    childLastActiveAt[child.pid] = now
                    hasActiveTransientToolChild = true
                } else if (now - (childLastActiveAt[child.pid] ?? firstSeen)) < Self.transientToolSilenceLimit {
                    hasActiveTransientToolChild = true
                } else {
                    baselineChildPIDs.insert(child.pid)
                }
            }
        }
        lastPollHadActiveToolChild = hasActiveTransientToolChild
        lastPollHadActiveBackgroundTask = hasActiveBackgroundTask

        // 4. Evaluate title spinner, active busy banners, and OSC 9;4 progress.
        //    Do not expire active busy banners or OSC 9;4 progress during long silent/2-frame-pulsing
        //    waits; clear stale OSC 9;4 progress immediately once an idle composer footer returns.
        let hasRecentTitleSpinner = lastSpinnerAnimationAt.map { (now - $0) <= 1.0 } ?? false
        if isProgressActive && hasIdleComposerFooter {
            isProgressActive = false
        }
        let hasLiveBusyBanner = hasExplicitBusyBanner
        let hasLiveProgress = isProgressActive && !hasIdleComposerFooter && detectedBlockedKind == nil

        let fallbackCPUWork = (viewport == nil) && hasHeavyAgentCPU && !isRecentTypingWindow && !inBootWindow
        let isRunningKeepAlive = autonomousNovelViewportChange
            || hasLiveBusyBanner
            || hasActiveTransientToolChild
            || hasRecentTitleSpinner
            || hasLiveProgress
            || fallbackCPUWork

        guard let current = status else { return false }

        if hasAuthoritativeHooks {
            switch current.phase {
            case .idle, .done:
                if isTabSelected, current.phase == .done {
                    status = AgentSessionStatus(agent: current.agent, phase: .idle)
                }
            case .needsInput:
                break
            case .running:
                if interruptedWhileAuthoritative,
                   let interruptedAt = lastInterruptAt,
                   (now - interruptedAt) >= Self.passiveSettleInterval,
                   hasIdleComposerFooter,
                   !hasExplicitBusyBanner,
                   !hasActiveTransientToolChild {
                    interruptedWhileAuthoritative = false
                    turnConfirmed = false
                    status = AgentSessionStatus(agent: current.agent, phase: .idle)
                }
            }
            return status != previous
        }

        switch current.phase {
        case .idle, .done:
            if isTabSelected, current.phase == .done {
                status = AgentSessionStatus(agent: current.agent, phase: .idle)
            }

            // Entering `.running` from idle/done requires a positive work signal — never bare
            // screen diffs alone (which false-trigger on TUI scrolling, resizing, or status ticks).
            if hasActiveBackgroundTask && !isRecentInteractionWindow {
                status = AgentSessionStatus(agent: current.agent, phase: .running)
                turnConfirmed = true
                lastWorkSignalAt = now
                lastCompletionHintAt = nil
                consecutiveWorkTicks = 0
            } else if hasExplicitBusyBanner && autonomousNovelViewportChange && !isRecentInteractionWindow {
                status = AgentSessionStatus(agent: current.agent, phase: .running)
                turnConfirmed = true
                lastWorkSignalAt = now
                lastCompletionHintAt = nil
                consecutiveWorkTicks = 0
            } else if let blockedKind = detectedBlockedKind,
                      !hasUnsubmittedTyping,
                      !isRecentTypingWindow,
                      !isRecentInteractionWindow,
                      !autonomousNovelViewportChange,
                      !hasActiveTransientToolChild,
                      !hasRecentTitleSpinner {
                isExplicitlyBlocked = false
                turnConfirmed = false
                consecutiveWorkTicks = 0
                lastCompletionHintAt = nil
                status = AgentSessionStatus(agent: current.agent, phase: .needsInput(blockedKind))
            } else if !inBootWindow, (hasRecentTitleSpinner || hasActiveTransientToolChild || fallbackCPUWork) {
                consecutiveWorkTicks += 1
                let requiredTicks = hasActiveTransientToolChild ? 1 : (hasRecentTitleSpinner ? 2 : 4)
                if consecutiveWorkTicks >= requiredTicks {
                    status = AgentSessionStatus(agent: current.agent, phase: .running)
                    turnConfirmed = true
                    lastWorkSignalAt = now
                    lastCompletionHintAt = nil
                }
            } else {
                consecutiveWorkTicks = 0
            }

        case .needsInput(let currentKind):
            if hasActiveTransientToolChild || hasRecentTitleSpinner || hasLiveProgress || (hasLiveBusyBanner && !isRecentInteractionWindow) {
                isExplicitlyBlocked = false
                status = AgentSessionStatus(agent: current.agent, phase: .running)
                turnConfirmed = true
                lastWorkSignalAt = now
                lastCompletionHintAt = nil
                consecutiveWorkTicks = 0
            } else if let blockedKind = detectedBlockedKind {
                if !isExplicitlyBlocked, blockedKind != currentKind {
                    status = AgentSessionStatus(agent: current.agent, phase: .needsInput(blockedKind))
                }
            } else if viewport != nil, !isExplicitlyBlocked, !isRecentInteractionWindow {
                // Interactive prompt disappeared from the viewport (e.g. single-key y/n or mouse click).
                if hasIdleComposerFooter && !autonomousNovelViewportChange {
                    status = AgentSessionStatus(agent: current.agent, phase: .idle)
                    turnConfirmed = false
                    hadTypedInputBeforeSubmit = false
                    consecutiveWorkTicks = 0
                } else {
                    status = AgentSessionStatus(agent: current.agent, phase: .running)
                    turnConfirmed = false
                    hadTypedInputBeforeSubmit = true
                    consecutiveWorkTicks = 0
                    lastWorkSignalAt = now
                    lastNovelScreenOrStartAt = now
                    lastCompletionHintAt = nil
                }
            }

        case .running:
            if isRunningKeepAlive {
                consecutiveWorkTicks += 1
                lastWorkSignalAt = now
                turnConfirmed = true
            } else {
                consecutiveWorkTicks = 0
                if let blockedKind = detectedBlockedKind,
                   (now - lastWorkSignalAt) >= Self.blockedSettleInterval {
                    isExplicitlyBlocked = false
                    turnConfirmed = false
                    hadTypedInputBeforeSubmit = false
                    lastCompletionHintAt = nil
                    status = AgentSessionStatus(agent: current.agent, phase: .needsInput(blockedKind))
                } else if !turnConfirmed {
                    let submitTimeout = hadTypedInputBeforeSubmit
                        ? Self.unconfirmedPromptSubmitTimeout
                        : Self.unconfirmedEmptySubmitTimeout
                    if (now - lastWorkSignalAt) >= submitTimeout {
                        status = AgentSessionStatus(agent: current.agent, phase: .idle)
                        hadTypedInputBeforeSubmit = false
                    }
                } else {
                    let hasRecentCompletionHint = lastCompletionHintAt.map {
                        $0 >= lastWorkSignalAt - 0.5 && (now - $0) <= 5.0
                    } ?? false
                    let settleThreshold = hasRecentCompletionHint
                        ? Self.hintedSettleInterval
                        : Self.passiveSettleInterval

                    if (now - lastWorkSignalAt) >= settleThreshold {
                        completeRunningTurn(for: current.agent, isTabSelected: isTabSelected)
                    }
                }
            }
        }

        return status != previous
    }

    private mutating func recordViewportHash(_ hash: UInt64) {
        if let existingIndex = recentViewportHashes.firstIndex(of: hash) {
            recentViewportHashes.remove(at: existingIndex)
        }
        recentViewportHashes.append(hash)
        if recentViewportHashes.count > Self.recentHistoryCapacity {
            recentViewportHashes.removeFirst(recentViewportHashes.count - Self.recentHistoryCapacity)
        }
    }

    private mutating func beginTrackingAgent(
        _ agent: AgentKind,
        rootPID: pid_t?,
        startsWorkingImmediately: Bool,
        now: TimeInterval
    ) {
        activeRootPID = rootPID
        isAgentProcessAlive = true
        isHeadlessRun = startsWorkingImmediately
        isExplicitlyBlocked = false
        hasAuthoritativeHooks = false
        interruptedWhileAuthoritative = false
        agentDetectedAt = now
        lastWorkSignalAt = now
        lastNovelScreenOrStartAt = now
        lastCompletionHintAt = nil
        lastInterruptAt = nil
        hadTypedInputBeforeSubmit = false
        pollsSinceSubmit = 0
        consecutiveWorkTicks = 0
        turnConfirmed = startsWorkingImmediately
        status = AgentSessionStatus(
            agent: agent,
            phase: startsWorkingImmediately ? .running : .idle
        )
        resetLiveMetrics()
    }

    private mutating func completeRunningTurn(for agent: AgentKind, isTabSelected: Bool) {
        turnConfirmed = false
        isHeadlessRun = false
        isExplicitlyBlocked = false
        interruptedWhileAuthoritative = false
        hadTypedInputBeforeSubmit = false
        consecutiveWorkTicks = 0
        lastCompletionHintAt = nil
        if isTabSelected {
            status = isAgentProcessAlive
                ? AgentSessionStatus(agent: agent, phase: .idle)
                : nil
        } else {
            status = AgentSessionStatus(agent: agent, phase: .done)
        }
    }

    private mutating func handleAbsentAgentProcess(isTabSelected: Bool) {
        guard let current = status else { return }
        if current.phase == .running, (turnConfirmed || isHeadlessRun), !isTabSelected {
            status = AgentSessionStatus(agent: current.agent, phase: .done)
            isAgentProcessAlive = false
            isHeadlessRun = false
            isExplicitlyBlocked = false
            hasAuthoritativeHooks = false
            interruptedWhileAuthoritative = false
            resetLiveMetrics()
        } else if current.phase == .done, !isTabSelected {
            isAgentProcessAlive = false
            isHeadlessRun = false
            isExplicitlyBlocked = false
            hasAuthoritativeHooks = false
            interruptedWhileAuthoritative = false
            resetLiveMetrics()
        } else {
            resetAll()
        }
    }

    private mutating func resetLiveMetrics() {
        recentViewportHashes.removeAll()
        hasInitializedViewport = false
        lastObservedViewportHash = nil
        dismissedBlockedViewportHash = nil
        previousTotalCPUNanos = nil
        childFirstSeenAt.removeAll()
        childLastActiveAt.removeAll()
        childPreviousCPUNanos.removeAll()
        baselineChildPIDs.removeAll()
        lastPollHadActiveToolChild = false
        lastPollHadActiveBackgroundTask = false
        lastSpinnerFrame = nil
        lastSpinnerAnimationAt = nil
        spinnerFrameTransitions = 0
        isProgressActive = false
    }

    private mutating func resetAll() {
        status = nil
        activeRootPID = nil
        isAgentProcessAlive = false
        isHeadlessRun = false
        isExplicitlyBlocked = false
        hasAuthoritativeHooks = false
        interruptedWhileAuthoritative = false
        turnConfirmed = false
        hadTypedInputBeforeSubmit = false
        pollsSinceSubmit = 0
        consecutiveWorkTicks = 0
        lastCompletionHintAt = nil
        lastUserTypingAt = nil
        lastUserSubmitAt = nil
        lastUserInteractionAt = nil
        lastInterruptAt = nil
        resetLiveMetrics()
    }
}

import Darwin
import Foundation

@MainActor
protocol AgentProcessInspecting: AnyObject {
    func inspect(foregroundPID: pid_t) -> AgentProcessObservation?
}

@MainActor
final class SystemAgentProcessInspector: AgentProcessInspecting {
    private struct ProcessCacheKey: Hashable {
        let pid: pid_t
        let startSeconds: UInt64
        let startMicroseconds: UInt64
    }

    private struct CachedIdentity {
        let match: AgentCommandMatch?
        let isHelperDaemon: Bool
    }

    private static let maxVisitedProcesses = 24
    private static let maxTreeDepth = 3
    private static let maxCacheEntries = 256

    private static let helperDaemonMarkers: [String] = [
        "mcp",
        "language-server",
        "language_server",
        "lsp",
        "antigravity",
        "esbuild",
        "watchman",
        "fsevents"
    ]

    private static let machTimebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        if info.denom == 0 {
            info.numer = 1
            info.denom = 1
        }
        return info
    }()

    private var identityCache: [ProcessCacheKey: CachedIdentity] = [:]

    func inspect(foregroundPID: pid_t) -> AgentProcessObservation? {
        guard foregroundPID > 0 else { return nil }

        struct VisitedNode {
            let pid: pid_t
            let parentPID: pid_t?
            let depth: Int
            let identity: CachedIdentity
        }

        var visited: [VisitedNode] = []
        var visitedPIDs: Set<pid_t> = []
        var queue: [(pid: pid_t, parent: pid_t?, depth: Int)] = [(foregroundPID, nil, 0)]
        var cursor = 0

        while cursor < queue.count, visited.count < Self.maxVisitedProcesses {
            let current = queue[cursor]
            cursor += 1

            guard visitedPIDs.insert(current.pid).inserted else { continue }
            guard let bsdInfo = Self.readBSDInfo(pid: current.pid) else { continue }

            let identity = resolveIdentity(pid: current.pid, bsdInfo: bsdInfo)
            visited.append(
                VisitedNode(
                    pid: current.pid,
                    parentPID: current.parent,
                    depth: current.depth,
                    identity: identity
                )
            )

            if current.depth < Self.maxTreeDepth {
                for childPID in Self.childPIDs(of: current.pid) {
                    if !visitedPIDs.contains(childPID) {
                        queue.append((childPID, current.pid, current.depth + 1))
                    }
                }
            }
        }

        guard let rootNode = visited.first(where: { $0.identity.match != nil }),
              let rootMatch = rootNode.identity.match
        else {
            return nil
        }

        var subtreePIDs: Set<pid_t> = [rootNode.pid]
        var changed = true
        while changed {
            changed = false
            for node in visited where !subtreePIDs.contains(node.pid) {
                if let parent = node.parentPID, subtreePIDs.contains(parent) {
                    subtreePIDs.insert(node.pid)
                    changed = true
                }
            }
        }

        var totalCPUNanos: UInt64 = 0
        var nonAgentChildren: [AgentChildProcessObservation] = []

        for node in visited where subtreePIDs.contains(node.pid) {
            let cpuNanos = Self.readCPUNanoseconds(pid: node.pid)
            totalCPUNanos &+= cpuNanos

            if node.pid != rootNode.pid, node.identity.match == nil {
                nonAgentChildren.append(
                    AgentChildProcessObservation(
                        pid: node.pid,
                        totalCPUNanoseconds: cpuNanos,
                        isHelperDaemon: node.identity.isHelperDaemon
                    )
                )
            }
        }

        return AgentProcessObservation(
            agent: rootMatch.agent,
            rootPID: rootNode.pid,
            startsWorkingImmediately: rootMatch.startsWorkingImmediately,
            totalCPUNanoseconds: totalCPUNanos,
            nonAgentChildren: nonAgentChildren
        )
    }

    private func resolveIdentity(pid: pid_t, bsdInfo: proc_bsdinfo) -> CachedIdentity {
        let key = ProcessCacheKey(
            pid: pid,
            startSeconds: bsdInfo.pbi_start_tvsec,
            startMicroseconds: bsdInfo.pbi_start_tvusec
        )
        if let cached = identityCache[key] {
            return cached
        }

        let match: AgentCommandMatch?
        let combinedLower: String
        if let procArgs = Self.readProcessArguments(pid: pid) {
            match = AgentCommandMatcher.match(
                executablePath: procArgs.executablePath,
                arguments: procArgs.arguments
            )
            combinedLower = ([procArgs.executablePath] + procArgs.arguments)
                .joined(separator: " ")
                .lowercased()
        } else {
            let execPath = Self.readProcessPath(pid: pid) ?? ""
            let fallbackName = Self.processName(from: bsdInfo)
            let args = fallbackName.isEmpty ? [] : [fallbackName]
            match = AgentCommandMatcher.match(executablePath: execPath, arguments: args)
            combinedLower = "\(execPath) \(fallbackName)".lowercased()
        }

        let isHelper = Self.helperDaemonMarkers.contains { combinedLower.contains($0) }
        let resolved = CachedIdentity(match: match, isHelperDaemon: isHelper)

        if identityCache.count >= Self.maxCacheEntries {
            identityCache.removeAll(keepingCapacity: true)
        }
        identityCache[key] = resolved
        return resolved
    }

    private static func readBSDInfo(pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let expected = Int32(MemoryLayout<proc_bsdinfo>.stride)
        let actual = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, expected)
        guard actual == expected else { return nil }
        return info
    }

    private static func readCPUNanoseconds(pid: pid_t) -> UInt64 {
        var taskInfo = proc_taskinfo()
        let expected = Int32(MemoryLayout<proc_taskinfo>.stride)
        let actual = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, expected)
        guard actual == expected else { return 0 }
        let machTicks = taskInfo.pti_total_user &+ taskInfo.pti_total_system
        let numer = UInt64(machTimebase.numer)
        let denom = UInt64(machTimebase.denom)
        let (product, overflow) = machTicks.multipliedReportingOverflow(by: numer)
        if overflow {
            return (machTicks / denom) * numer
        }
        return product / denom
    }

    private static func childPIDs(of pid: pid_t) -> [pid_t] {
        let estimatedBytes = proc_listchildpids(pid, nil, 0)
        guard estimatedBytes > 0 else { return [] }
        let capacity = max(Int(estimatedBytes) / MemoryLayout<pid_t>.stride + 4, 8)
        var buffer = [pid_t](repeating: 0, count: capacity)
        let writtenBytes = proc_listchildpids(
            pid,
            &buffer,
            Int32(buffer.count * MemoryLayout<pid_t>.stride)
        )
        guard writtenBytes > 0 else { return [] }
        let count = min(Int(writtenBytes) / MemoryLayout<pid_t>.stride, buffer.count)
        return buffer.prefix(count).filter { $0 > 0 }
    }

    private static func readProcessPath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func processName(from bsdInfo: proc_bsdinfo) -> String {
        let name = withUnsafePointer(to: bsdInfo.pbi_name) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) * 2) {
                String(cString: $0)
            }
        }
        if !name.isEmpty { return name }
        return withUnsafePointer(to: bsdInfo.pbi_comm) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) {
                String(cString: $0)
            }
        }
    }

    private static func readProcessArguments(
        pid: pid_t
    ) -> (executablePath: String, arguments: [String])? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var neededSize = 0
        if sysctl(&mib, 3, nil, &neededSize, nil, 0) != 0 || neededSize <= MemoryLayout<Int32>.size {
            neededSize = 64 * 1024
        } else {
            neededSize = min(max(neededSize + 256, 512), 256 * 1024)
        }

        var buffer = [UInt8](repeating: 0, count: neededSize)
        var size = buffer.count
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0,
              size > MemoryLayout<Int32>.size
        else {
            return nil
        }

        let argc = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc > 0 else { return nil }

        var index = MemoryLayout<Int32>.size
        while index < size && buffer[index] != 0 {
            index += 1
        }
        let execPath = String(
            decoding: buffer[MemoryLayout<Int32>.size..<index],
            as: UTF8.self
        )

        while index < size && buffer[index] == 0 {
            index += 1
        }

        let maxArguments = Int(min(argc, 24))
        var arguments: [String] = []
        arguments.reserveCapacity(maxArguments)

        while index < size && arguments.count < maxArguments {
            let start = index
            while index < size && buffer[index] != 0 {
                index += 1
            }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }

        return (execPath, arguments)
    }
}

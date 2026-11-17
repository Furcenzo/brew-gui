// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import Foundation

public enum ProcessEvent: Sendable {
    case output(String)
    case exit(Int32)
}

public struct CommandError: LocalizedError, Sendable {
    public var command: String
    public var status: Int32
    public var stderr: String

    public init(command: String, status: Int32, stderr: String) {
        self.command = command
        self.status = status
        self.stderr = stderr
    }

    public var errorDescription: String? {
        let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(localized: "Command `\(command)` exited with code \(status).") + (detail.isEmpty ? "" : "\n\n\(detail)")
    }
}

private final class ProcessBox: @unchecked Sendable {
    let process = Process()
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

/// Splits incoming bytes into lines (also across UTF‑8 character boundaries).
struct LineSplitter {
    private var buffer = Data()

    mutating func feed(_ data: Data) -> [String] {
        buffer.append(data)
        var lines: [String] = []
        while let index = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let lineData = buffer[buffer.startIndex..<index]
            buffer.removeSubrange(buffer.startIndex...index)
            let line = String(decoding: lineData, as: UTF8.self)
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }

    mutating func flush() -> String? {
        defer { buffer.removeAll() }
        let line = String(decoding: buffer, as: UTF8.self)
        return line.isEmpty ? nil : line
    }
}

public enum ProcessRunner {
    private static let ansi = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[A-Za-z]")

    static func stripANSI(_ text: String) -> String {
        ansi.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
    }

    /// Runs a process and streams its output (stdout + stderr) line by line.
    /// Cancelling the stream sends SIGINT to the process.
    public static func stream(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL? = nil
    ) -> AsyncThrowingStream<ProcessEvent, Error> {
        AsyncThrowingStream { continuation in
            let box = ProcessBox()
            let process = box.process
            process.executableURL = executable
            process.arguments = arguments
            process.environment = environment
            if let currentDirectory { process.currentDirectoryURL = currentDirectory }
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                continuation.finish(throwing: error)
                return
            }

            let handle = pipe.fileHandleForReading
            DispatchQueue.global(qos: .userInitiated).async {
                var splitter = LineSplitter()
                while true {
                    let data = handle.availableData
                    if data.isEmpty { break }
                    for line in splitter.feed(data) { continuation.yield(.output(stripANSI(line))) }
                }
                if let last = splitter.flush() { continuation.yield(.output(stripANSI(last))) }
                box.process.waitUntilExit()
                continuation.yield(.exit(box.process.terminationStatus))
                continuation.finish()
            }

            continuation.onTermination = { reason in
                if case .cancelled = reason, box.process.isRunning {
                    box.process.interrupt()
                }
            }
        }
    }

    /// Runs a process and returns its whole stdout. Throws `CommandError` on a non-zero exit code.
    public static func capture(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        allowFailure: Bool = false
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                process.environment = environment
                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err
                process.standardInput = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                let errBox = DataBox()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    errBox.data = err.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()

                let stdout = String(decoding: outData, as: UTF8.self)
                if process.terminationStatus != 0, !allowFailure {
                    let command = ([executable.lastPathComponent] + arguments).joined(separator: " ")
                    continuation.resume(throwing: CommandError(
                        command: command,
                        status: process.terminationStatus,
                        stderr: stripANSI(String(decoding: errBox.data, as: UTF8.self))
                    ))
                } else {
                    continuation.resume(returning: stripANSI(stdout))
                }
            }
        }
    }
}

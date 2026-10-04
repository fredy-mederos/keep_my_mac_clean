import Foundation

public enum CommandRunner {
    public struct Output: Sendable {
        public var status: Int32
        public var stdout: String
        public var stderr: String
    }

    public enum Failure: Error, LocalizedError {
        case timedOut(String)

        public var errorDescription: String? {
            switch self {
            case .timedOut(let command): "\(command) took too long and was stopped."
            }
        }
    }

    /// Runs a command and waits for it. Blocking: call it off the main thread.
    public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 120) throws -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        try process.run()

        // Drain stderr concurrently so a chatty command can't fill the pipe and deadlock.
        let stderrData = DataBox()
        let stderrDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            stderrData.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            stderrDone.signal()
        }

        let timedOut = TimeoutFlag()
        let timer = DispatchWorkItem {
            if process.isRunning {
                timedOut.value = true
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timer.cancel()
        stderrDone.wait()

        if timedOut.value {
            throw Failure.timedOut(([executable] + arguments).joined(separator: " "))
        }
        return Output(
            status: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData.data, as: UTF8.self)
        )
    }

    private final class DataBox: @unchecked Sendable {
        var data = Data()
    }

    private final class TimeoutFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var _value = false
        var value: Bool {
            get { lock.withLock { _value } }
            set { lock.withLock { _value = newValue } }
        }
    }
}

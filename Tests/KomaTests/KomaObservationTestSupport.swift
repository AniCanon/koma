import Foundation

actor ObservationProbe<Element: Sendable> {
    private var values: [Element] = []
    private var waiters: [(count: Int, continuation: CheckedContinuation<[Element], Never>)] = []

    func append(_ value: Element) {
        values.append(value)
        resumeSatisfiedWaiters()
    }

    func waitForCount(_ count: Int) async -> [Element] {
        if values.count >= count {
            return values
        }

        return await withCheckedContinuation { continuation in
            waiters.append((count, continuation))
        }
    }

    func snapshot() -> [Element] {
        values
    }

    private func resumeSatisfiedWaiters() {
        var remaining: [(count: Int, continuation: CheckedContinuation<[Element], Never>)] = []
        for waiter in waiters {
            if values.count >= waiter.count {
                waiter.continuation.resume(returning: values)
            } else {
                remaining.append(waiter)
            }
        }
        waiters = remaining
    }
}

enum ObservationTimeoutError: Error {
    case timedOut
}

func withObservationTimeout<Value: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: duration)
            throw ObservationTimeoutError.timedOut
        }

        guard let value = try await group.next() else {
            throw ObservationTimeoutError.timedOut
        }
        group.cancelAll()
        return value
    }
}

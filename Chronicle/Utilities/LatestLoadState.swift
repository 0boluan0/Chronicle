//
//  LatestLoadState.swift
//  Chronicle
//

import Foundation

/// Tracks one family of replaceable asynchronous loads. A completion may
/// mutate view state only when its token still belongs to the newest request.
struct LatestLoadLifecycle {
    private(set) var generation: UInt64 = 0
    private(set) var isLoading = false
    private(set) var hasSuccessfulLoad = false
    private(set) var errorDescription: String?

    init(initiallyLoading: Bool = false) {
        isLoading = initiallyLoading
    }

    mutating func begin() -> UInt64 {
        generation &+= 1
        isLoading = true
        return generation
    }

    @discardableResult
    mutating func complete(
        token: UInt64,
        errorDescription: String?,
        didLoadSuccessfully: Bool
    ) -> Bool {
        guard token == generation, isLoading else { return false }
        isLoading = false
        self.errorDescription = errorDescription
        if didLoadSuccessfully {
            hasSuccessfulLoad = true
        }
        return true
    }
}

/// A latest-request-wins value that retains its last successful value when a
/// refresh fails.
struct LatestValueLoadState<Value> {
    private(set) var value: Value
    private(set) var lifecycle: LatestLoadLifecycle

    init(initialValue: Value, initiallyLoading: Bool = false) {
        value = initialValue
        lifecycle = LatestLoadLifecycle(initiallyLoading: initiallyLoading)
    }

    var isLoading: Bool { lifecycle.isLoading }
    var hasSuccessfulValue: Bool { lifecycle.hasSuccessfulLoad }
    var errorDescription: String? { lifecycle.errorDescription }

    mutating func begin() -> UInt64 {
        lifecycle.begin()
    }

    @discardableResult
    mutating func complete<Failure: Error>(
        token: UInt64,
        result: Result<Value, Failure>,
        describeFailure: (Failure) -> String
    ) -> Bool {
        guard token == lifecycle.generation, lifecycle.isLoading else { return false }

        switch result {
        case .success(let newValue):
            guard lifecycle.complete(
                token: token,
                errorDescription: nil,
                didLoadSuccessfully: true
            ) else { return false }
            value = newValue
        case .failure(let error):
            guard lifecycle.complete(
                token: token,
                errorDescription: describeFailure(error),
                didLoadSuccessfully: false
            ) else { return false }
        }
        return true
    }
}

/// A section in a multi-query load. Failed sections resolve to their previous
/// successful value instead of masquerading as an empty response.
enum PartialLoadResult<Value> {
    case success(Value)
    case failure(String)

    var didSucceed: Bool {
        if case .success = self { return true }
        return false
    }

    var errorDescription: String? {
        if case .failure(let description) = self { return description }
        return nil
    }

    func resolving(preserving previousValue: Value) -> Value {
        switch self {
        case .success(let value):
            return value
        case .failure:
            return previousValue
        }
    }
}

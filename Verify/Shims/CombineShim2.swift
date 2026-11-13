import Foundation

// ---- Combine 最小桩（独立模块）

public protocol Publisher {
    associatedtype Output
    associatedtype Failure: Error
}

public protocol ObservableObject: AnyObject {
    associatedtype ObjectWillChangePublisher: Publisher = ObservableObjectPublisher
        where ObjectWillChangePublisher.Failure == Never
    var objectWillChange: ObjectWillChangePublisher { get }
}

extension ObservableObject {
    public var objectWillChange: ObservableObjectPublisher { ObservableObjectPublisher() }
}

public struct ObservableObjectPublisher: Publisher {
    public typealias Output = Void
    public typealias Failure = Never
    public init() {}
    public func send() {}
}

@propertyWrapper
public struct Published<Value> {
    private final class Storage { var value: Value; init(_ v: Value) { value = v } }
    private let storage: Storage
    public var wrappedValue: Value {
        get { storage.value }
        nonmutating set { storage.value = newValue }
    }
    public var projectedValue: Published<Value>.Publisher { Publisher() }
    public init(wrappedValue: Value) { storage = Storage(wrappedValue) }
    public init(initialValue: Value) { storage = Storage(initialValue) }

    public struct Publisher: Combine.Publisher {
        public typealias Output = Value
        public typealias Failure = Never
        public init() {}
    }
}

public struct AnyPublisher<Output, Failure: Error>: Publisher {
    public init<Upstream: Publisher>(_ upstream: Upstream)
        where Upstream.Output == Output, Upstream.Failure == Failure {}
}

public struct PassthroughSubject<Output, Failure: Error>: Publisher {
    public init() {}
    public func send(_ v: Output) {}
}

public struct CurrentValueSubject<Output, Failure: Error>: Publisher {
    public init(_ v: Output) {}
    public func send(_ v: Output) {}
}

public struct Just<Output>: Publisher {
    public typealias Failure = Never
    public init(_ v: Output) {}
}

public struct Empty<Output, Failure: Error>: Publisher {
    public init() {}
}

extension Publisher {
    public func sink(receiveValue: @escaping (Output) -> Void) -> AnyCancellable { AnyCancellable() }
    public func eraseToAnyPublisher() -> AnyPublisher<Output, Failure> { AnyPublisher(self) }
    public func debounce<S: Scheduler>(for: Double, scheduler: S) -> AnyPublisher<Output, Failure> { eraseToAnyPublisher() }
    public func removeDuplicates() -> AnyPublisher<Output, Failure> where Output: Equatable { eraseToAnyPublisher() }
    public func receive(on: DispatchQueue) -> AnyPublisher<Output, Failure> { eraseToAnyPublisher() }
}

public final class AnyCancellable: Hashable {
    public init() {}
    public init(_ cancel: @escaping () -> Void) {}
    public func cancel() {}
    public func hash(into hasher: inout Hasher) {}
    public static func == (l: AnyCancellable, r: AnyCancellable) -> Bool { l === r }
}

public protocol Scheduler {}
extension DispatchQueue: Scheduler {}

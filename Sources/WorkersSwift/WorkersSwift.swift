import Foundation

public struct WorkerRequest: Sendable, Equatable {
    public let method: String
    public let path: String

    public init(method: String, path: String) {
        self.method = method
        self.path = path
    }
}

public struct WorkerResponse: Sendable, Equatable {
    public let status: Int
    public let headers: [String: String]
    public let body: String

    public init(status: Int, headers: [String: String] = ["content-type": "text/plain; charset=utf-8"], body: String) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

public enum WorkersSwiftApp {
    public static func handle(_ request: WorkerRequest) -> WorkerResponse {
        switch (request.method.uppercased(), request.path) {
        case ("GET", "/"):
            return WorkerResponse(status: 200, body: "Hello from Swift on workerd/celld")
        case ("GET", "/health"):
            return WorkerResponse(status: 200, body: "ok")
        default:
            return WorkerResponse(status: 404, body: "Not Found")
        }
    }
}

private struct StoredWasmResponse {
    let status: Int32
    let body: [UInt8]
}

private struct WasmAllocation {
    let size: Int32
    let alignment: Int32
}

enum WasmResponseStore {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var nextHandle: Int32 = 1
    nonisolated(unsafe) private static var responses: [Int32: StoredWasmResponse] = [:]

    static func store(_ response: WorkerResponse) -> Int32 {
        let storedResponse = StoredWasmResponse(
            status: Int32(response.status),
            body: Array(response.body.utf8)
        )

        lock.lock()
        defer { lock.unlock() }

        let handle = nextHandle
        nextHandle &+= 1
        responses[handle] = storedResponse
        return handle
    }

    static func status(for handle: Int32) -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        return responses[handle]?.status ?? 500
    }

    static func bodyLength(for handle: Int32) -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        return Int32(responses[handle]?.body.count ?? 0)
    }

    static func copyBody(for handle: Int32, to destination: UnsafeMutableRawPointer?) {
        guard let destination else {
            return
        }

        lock.lock()
        let body = responses[handle]?.body ?? []
        lock.unlock()

        guard !body.isEmpty else {
            return
        }

        body.withUnsafeBytes { bytes in
            destination.copyMemory(from: bytes.baseAddress!, byteCount: body.count)
        }
    }

    static func release(_ handle: Int32) {
        lock.lock()
        defer { lock.unlock() }
        responses.removeValue(forKey: handle)
    }
}

enum WasmAllocationStore {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var allocations: [UInt: WasmAllocation] = [:]

    static func record(pointer: UnsafeMutableRawPointer, size: Int32, alignment: Int32) {
        lock.lock()
        defer { lock.unlock() }
        allocations[UInt(bitPattern: pointer)] = WasmAllocation(size: size, alignment: alignment)
    }

    static func take(pointer: UnsafeMutableRawPointer, size: Int32, alignment: Int32) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let key = UInt(bitPattern: pointer)
        guard let allocation = allocations[key] else {
            return false
        }
        guard allocation.size == size, allocation.alignment == alignment else {
            return false
        }

        allocations.removeValue(forKey: key)
        return true
    }
}

func decodeUTF8(_ pointer: UnsafePointer<UInt8>?, _ length: Int32) -> String {
    guard let pointer, length > 0 else {
        return ""
    }

    let buffer = UnsafeBufferPointer(start: pointer, count: Int(length))
    return String(decoding: buffer, as: UTF8.self)
}

#if arch(wasm32)
@_expose(wasm, "workers_alloc")
#endif
@_cdecl("workers_alloc")
public func workers_alloc(_ size: Int32, _ alignment: Int32) -> UnsafeMutableRawPointer? {
    guard size >= 0, alignment > 0 else {
        return nil
    }

    let pointer = UnsafeMutableRawPointer.allocate(byteCount: max(Int(size), 1), alignment: Int(alignment))
    WasmAllocationStore.record(pointer: pointer, size: size, alignment: alignment)
    return pointer
}

#if arch(wasm32)
@_expose(wasm, "workers_free")
#endif
@_cdecl("workers_free")
public func workers_free(_ pointer: UnsafeMutableRawPointer?, _ size: Int32, _ alignment: Int32) {
    guard let pointer, size >= 0, alignment > 0 else {
        return
    }
    guard WasmAllocationStore.take(pointer: pointer, size: size, alignment: alignment) else {
        return
    }

    pointer.deallocate()
}

#if arch(wasm32)
@_expose(wasm, "workers_handle_request")
#endif
@_cdecl("workers_handle_request")
public func workers_handle_request(
    _ methodPointer: UnsafePointer<UInt8>?,
    _ methodLength: Int32,
    _ pathPointer: UnsafePointer<UInt8>?,
    _ pathLength: Int32
) -> Int32 {
    let request = WorkerRequest(
        method: decodeUTF8(methodPointer, methodLength),
        path: decodeUTF8(pathPointer, pathLength)
    )

    let response = WorkersSwiftApp.handle(request)
    return WasmResponseStore.store(response)
}

#if arch(wasm32)
@_expose(wasm, "workers_response_status")
#endif
@_cdecl("workers_response_status")
public func workers_response_status(_ handle: Int32) -> Int32 {
    WasmResponseStore.status(for: handle)
}

#if arch(wasm32)
@_expose(wasm, "workers_response_body_len")
#endif
@_cdecl("workers_response_body_len")
public func workers_response_body_len(_ handle: Int32) -> Int32 {
    WasmResponseStore.bodyLength(for: handle)
}

#if arch(wasm32)
@_expose(wasm, "workers_response_body_copy")
#endif
@_cdecl("workers_response_body_copy")
public func workers_response_body_copy(_ handle: Int32, _ destination: UnsafeMutableRawPointer?) {
    WasmResponseStore.copyBody(for: handle, to: destination)
}

#if arch(wasm32)
@_expose(wasm, "workers_response_release")
#endif
@_cdecl("workers_response_release")
public func workers_response_release(_ handle: Int32) {
    WasmResponseStore.release(handle)
}

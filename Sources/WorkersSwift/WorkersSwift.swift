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

enum WasmResponseBuffer {
    nonisolated(unsafe) private static var pointer: UnsafeMutablePointer<UInt8>?
    nonisolated(unsafe) private static var length: Int = 0

    static func replace(with body: String) {
        reset()

        let bytes = Array(body.utf8)
        guard !bytes.isEmpty else {
            return
        }

        let newPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: bytes.count)
        newPointer.initialize(from: bytes, count: bytes.count)
        pointer = newPointer
        length = bytes.count
    }

    static func bodyPointer() -> UnsafePointer<UInt8>? {
        guard let pointer else {
            return nil
        }
        return UnsafePointer(pointer)
    }

    static func bodyLength() -> Int32 {
        Int32(length)
    }

    private static func reset() {
        pointer?.deallocate()
        pointer = nil
        length = 0
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
public func workers_alloc(_ size: Int32) -> UnsafeMutablePointer<UInt8>? {
    guard size > 0 else {
        return nil
    }

    return UnsafeMutablePointer<UInt8>.allocate(capacity: Int(size))
}

#if arch(wasm32)
@_expose(wasm, "workers_free")
#endif
@_cdecl("workers_free")
public func workers_free(_ pointer: UnsafeMutablePointer<UInt8>?, _ size: Int32) {
    guard size > 0 else {
        return
    }

    pointer?.deallocate()
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
    WasmResponseBuffer.replace(with: response.body)
    return Int32(response.status)
}

#if arch(wasm32)
@_expose(wasm, "workers_response_body_ptr")
#endif
@_cdecl("workers_response_body_ptr")
public func workers_response_body_ptr() -> UnsafePointer<UInt8>? {
    WasmResponseBuffer.bodyPointer()
}

#if arch(wasm32)
@_expose(wasm, "workers_response_body_len")
#endif
@_cdecl("workers_response_body_len")
public func workers_response_body_len() -> Int32 {
    WasmResponseBuffer.bodyLength()
}

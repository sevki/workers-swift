import Testing
@testable import WorkersSwift

@Test func rootRequestReturnsHelloMessage() async throws {
    let response = WorkersSwiftApp.handle(.init(method: "GET", path: "/"))

    #expect(response.status == 200)
    #expect(response.body == "Hello from Swift on workerd/celld")
    #expect(response.headers["content-type"] == "text/plain; charset=utf-8")
}

@Test func healthRequestReturnsOk() async throws {
    let response = WorkersSwiftApp.handle(.init(method: "GET", path: "/health"))

    #expect(response.status == 200)
    #expect(response.body == "ok")
}

@Test func unknownRouteReturnsNotFound() async throws {
    let response = WorkersSwiftApp.handle(.init(method: "POST", path: "/missing"))

    #expect(response.status == 404)
    #expect(response.body == "Not Found")
}

@Test func lowercaseMethodStillMatchesRoute() async throws {
    let response = WorkersSwiftApp.handle(.init(method: "get", path: "/health"))

    #expect(response.status == 200)
    #expect(response.body == "ok")
}

@Test func mixedCaseNonGetMethodStillMissesGetRoute() async throws {
    let response = WorkersSwiftApp.handle(.init(method: "PoSt", path: "/health"))

    #expect(response.status == 404)
    #expect(response.body == "Not Found")
}

@Test func wasmRequestExportsRoundTripResponseBody() async throws {
    let method = Array("GET".utf8)
    let path = Array("/".utf8)

    let handle = method.withUnsafeBufferPointer { methodBuffer in
        path.withUnsafeBufferPointer { pathBuffer in
            workers_handle_request(
                methodBuffer.baseAddress,
                Int32(methodBuffer.count),
                pathBuffer.baseAddress,
                Int32(pathBuffer.count)
            )
        }
    }

    #expect(workers_response_status(handle) == 200)
    let bodyLength = workers_response_body_len(handle)
    #expect(bodyLength == Int32("Hello from Swift on workerd/celld".utf8.count))

    let bodyPointer = workers_alloc(bodyLength, 1)
    #expect(bodyPointer != nil)

    workers_response_body_copy(handle, bodyPointer)

    let body = String(
        decoding: UnsafeBufferPointer(
            start: bodyPointer?.assumingMemoryBound(to: UInt8.self),
            count: Int(bodyLength)
        ),
        as: UTF8.self
    )

    #expect(body == "Hello from Swift on workerd/celld")

    workers_free(bodyPointer, bodyLength, 1)
    workers_response_release(handle)
    #expect(workers_response_status(handle) == 500)
}

@Test func wasmAllocatorRejectsNegativeSizesAndSupportsEmptyBuffers() async throws {
    #expect(workers_alloc(-1, 1) == nil)

    let empty = workers_alloc(0, 1)
    #expect(empty != nil)
    workers_free(empty, 0, 1)
}

@Test func wasmAllocatorRejectsInvalidAlignment() async throws {
    #expect(workers_alloc(4, 3) == nil)
}

@Test func wasmRequestRejectsNegativeLengths() async throws {
    let method = Array("GET".utf8)

    let handle = method.withUnsafeBufferPointer { methodBuffer in
        workers_handle_request(methodBuffer.baseAddress, -1, nil, 0)
    }

    #expect(handle == 0)
}

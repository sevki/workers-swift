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

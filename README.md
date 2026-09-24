# workers-swift

A tiny Swift starting point for a `workers-rs`-style project that can be compiled to WebAssembly and loaded by both [workerd](https://github.com/cloudflare/workerd) and [denoland/celld](https://github.com/denoland/celld).

## What is in this repository?

- `Sources/WorkersSwift/WorkersSwift.swift` contains a minimal Workers-style request/response core.
- `Examples/workerd-celld/worker.mjs` is a JavaScript shim that instantiates the compiled Swift WebAssembly module and forwards `fetch` requests into Swift.
- `Tests/WorkersSwiftTests/WorkersSwiftTests.swift` covers the Swift request handling behavior.

## Native development

The package is intentionally kept compatible with the currently installed Swift 6.3.3 toolchain for local development:

```bash
swift test
```

## Building for WebAssembly

Swift 6.4.0 is the latest release line to target when you install a WebAssembly SDK.

1. Install a Swift WebAssembly SDK and confirm the SDK identifier:

   ```bash
   swift sdk list
   ```

2. Build the package as a reactor-style WebAssembly module. Replace `<swift-wasm-sdk-id>` with your installed SDK identifier (for example a `..._wasm-embedded` SDK on Swift 6.4.0):

   ```bash
   swift build \
     --swift-sdk <swift-wasm-sdk-id> \
     -c release \
     -Xswiftc -parse-as-library \
     -Xlinker -mexec-model=reactor
   ```

3. Copy the produced `WorkersSwift.wasm` next to `Examples/workerd-celld/worker.mjs` as `WorkersSwift.wasm`.

The JavaScript shim expects these WebAssembly exports:

- `workers_alloc`
- `workers_free`
- `workers_handle_request`
- `workers_response_status`
- `workers_response_body_len`
- `workers_response_body_copy`
- `workers_response_release`
- `memory`

## Using with workerd or celld

Use `Examples/workerd-celld/worker.mjs` as the Worker entry point. The same module shape works for both runtimes because they both expose the standard Worker `fetch` interface and can instantiate bundled `.wasm` modules from JavaScript. The shim reads optional host imports from `globalThis.swiftWasmImportObject`, which lets you provide WASI or other runtime imports when your chosen Swift WebAssembly SDK needs them.

The default Swift routes are:

- `GET /` → `200 Hello from Swift on workerd/celld`
- `GET /health` → `200 ok`
- everything else → `404 Not Found`

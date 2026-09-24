import wasmModule from "./WorkersSwift.wasm";

const encoder = new TextEncoder();
const decoder = new TextDecoder();
const WASM_ALIGNMENT = 1;

function writeString(instance, value) {
  const bytes = encoder.encode(value);
  const pointer = instance.exports.workers_alloc(bytes.length, WASM_ALIGNMENT);

  if ((pointer === 0 || pointer == null) && bytes.length > 0) {
    throw new Error("Swift Wasm allocation failed for request string");
  }

  if (bytes.length > 0) {
    new Uint8Array(instance.exports.memory.buffer, pointer, bytes.length).set(bytes);
  }

  return { pointer, length: bytes.length, alignment: WASM_ALIGNMENT };
}

function readCopiedString(instance, handle) {
  const length = instance.exports.workers_response_body_len(handle);
  if (!length) {
    return "";
  }

  const pointer = instance.exports.workers_alloc(length, WASM_ALIGNMENT);
  if (pointer === 0 || pointer == null) {
    throw new Error("Swift Wasm allocation failed for response body copy");
  }

  try {
    instance.exports.workers_response_body_copy(handle, pointer);
    return decoder.decode(new Uint8Array(instance.exports.memory.buffer, pointer, length));
  } finally {
    instance.exports.workers_free(pointer, length, WASM_ALIGNMENT);
  }
}

export function createWorkerHandler(importObject = {}) {
  let instancePromise;

  async function loadInstance() {
    if (!instancePromise) {
      instancePromise = WebAssembly.instantiate(wasmModule, importObject).catch((error) => {
        instancePromise = undefined;
        throw error;
      });
    }

    const { instance } = await instancePromise;
    return instance;
  }

  return {
    async fetch(request) {
      const instance = await loadInstance();
      const url = new URL(request.url);
      const method = writeString(instance, request.method);
      const path = writeString(instance, url.pathname);

      let handle = 0;

      try {
        handle = instance.exports.workers_handle_request(
          method.pointer,
          method.length,
          path.pointer,
          path.length,
        );
        const status = instance.exports.workers_response_status(handle);
        const body = readCopiedString(instance, handle);

        return new Response(body, {
          status,
          headers: {
            "content-type": "text/plain; charset=utf-8",
          },
        });
      } finally {
        instance.exports.workers_free(method.pointer, method.length, method.alignment);
        instance.exports.workers_free(path.pointer, path.length, path.alignment);

        if (handle) {
          instance.exports.workers_response_release(handle);
        }
      }
    },
  };
}

const defaultImportObject = globalThis.swiftWasmImportObject ?? {};

export default createWorkerHandler(defaultImportObject);

import wasmModule from "./WorkersSwift.wasm";

const encoder = new TextEncoder();
const decoder = new TextDecoder();

let instancePromise;

async function loadInstance(importObject) {
  if (!instancePromise) {
    instancePromise = WebAssembly.instantiate(wasmModule, importObject);
  }

  const { instance } = await instancePromise;
  return instance;
}

function writeString(instance, value) {
  const bytes = encoder.encode(value);
  const pointer = instance.exports.workers_alloc(bytes.length);

  if (bytes.length > 0) {
    new Uint8Array(instance.exports.memory.buffer, pointer, bytes.length).set(bytes);
  }

  return { pointer, length: bytes.length };
}

function readCopiedString(instance, handle) {
  const length = instance.exports.workers_response_body_len(handle);
  if (!length) {
    return "";
  }

  const pointer = instance.exports.workers_alloc(length);

  try {
    instance.exports.workers_response_body_copy(handle, pointer);
    return decoder.decode(new Uint8Array(instance.exports.memory.buffer, pointer, length));
  } finally {
    instance.exports.workers_free(pointer, length);
  }
}

export function createWorkerHandler(importObject = globalThis.swiftWasmImportObject ?? {}) {
  return {
    async fetch(request) {
      const instance = await loadInstance(importObject);
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
        instance.exports.workers_free(method.pointer, method.length);
        instance.exports.workers_free(path.pointer, path.length);

        if (handle) {
          instance.exports.workers_response_release(handle);
        }
      }
    },
  };
}

export default createWorkerHandler();

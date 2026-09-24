import wasmModule from "./WorkersSwift.wasm";

const encoder = new TextEncoder();
const decoder = new TextDecoder();

let instancePromise;

async function loadInstance() {
  if (!instancePromise) {
    instancePromise = WebAssembly.instantiate(wasmModule, {});
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

function readString(instance, pointer, length) {
  if (!pointer || !length) {
    return "";
  }

  return decoder.decode(new Uint8Array(instance.exports.memory.buffer, pointer, length));
}

export default {
  async fetch(request) {
    const instance = await loadInstance();
    const url = new URL(request.url);
    const method = writeString(instance, request.method);
    const path = writeString(instance, url.pathname);

    try {
      const status = instance.exports.workers_handle_request(
        method.pointer,
        method.length,
        path.pointer,
        path.length,
      );
      const bodyPointer = instance.exports.workers_response_body_ptr();
      const bodyLength = instance.exports.workers_response_body_len();
      const body = readString(instance, bodyPointer, bodyLength);

      return new Response(body, {
        status,
        headers: {
          "content-type": "text/plain; charset=utf-8",
        },
      });
    } finally {
      instance.exports.workers_free(method.pointer, method.length);
      instance.exports.workers_free(path.pointer, path.length);
    }
  },
};

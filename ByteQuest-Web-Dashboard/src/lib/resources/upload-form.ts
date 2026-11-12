import { MAX_LEARNING_RESOURCE_BYTES } from "./policy";

export class UploadSizeError extends Error {}
/** Bound streamed/chunked requests as well as requests with Content-Length. */
export async function readResourceForm(
  request: Request,
  maxBytes = MAX_LEARNING_RESOURCE_BYTES + 64 * 1024,
) {
  if (Number(request.headers.get("content-length")) > maxBytes)
    throw new UploadSizeError();
  const reader = request.body?.getReader();
  if (!reader) throw new Error("UPLOAD_BODY_REQUIRED");
  let total = 0;
  const body = new ReadableStream<Uint8Array>({
    async pull(controller) {
      try {
        const { done, value } = await reader.read();
        if (done) {
          controller.close();
          return;
        }
        total += value.byteLength;
        if (total > maxBytes) {
          await reader.cancel();
          controller.error(new UploadSizeError());
          return;
        }
        controller.enqueue(value);
      } catch (error) {
        controller.error(error);
      }
    },
    cancel() {
      return reader.cancel();
    },
  });
  try {
    return await new Response(body, {
      headers: { "Content-Type": request.headers.get("content-type") ?? "" },
    }).formData();
  } catch (error) {
    if (total > maxBytes) throw new UploadSizeError();
    throw error;
  }
}

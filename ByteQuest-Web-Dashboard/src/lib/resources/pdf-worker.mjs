import { parentPort, workerData } from "node:worker_threads";

// No URL input, embedded script execution, attachments, OCR or document writes.
// Reference text stays in this request's memory and is never logged.
console.log = console.warn = console.error = () => {};
try {
  const { getDocument } = await import("pdfjs-dist/legacy/build/pdf.mjs");
  const task = getDocument({
    data: new Uint8Array(workerData.bytes),
    verbosity: 0,
    isEvalSupported: false,
    useWasm: false,
    useWorkerFetch: false,
    disableFontFace: true,
    useSystemFonts: false,
    enableXfa: false,
    stopAtErrors: true,
  });
  task.onPassword = () => {
    parentPort.postMessage({ error: "PDF_ENCRYPTED" });
    void task.destroy();
  };
  const doc = await task.promise;
  if (doc.numPages > 50) throw new Error("PDF_TOO_LONG");
  let text = "";
  for (let number = 1; number <= doc.numPages; number++) {
    const page = await doc.getPage(number);
    const content = await page.getTextContent();
    text +=
      content.items
        .filter((item) => typeof item.str === "string")
        .map((item) => item.str)
        .join(" ") + "\n";
    page.cleanup();
    if (text.length > 48_000) throw new Error("PDF_TOO_LONG");
  }
  const pages = doc.numPages;
  await task.destroy();
  text = text.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, "").trim();
  if (text.replace(/\s/g, "").length < 80 || !/\p{L}{3}/u.test(text))
    throw new Error("PDF_NO_TEXT");
  parentPort.postMessage({ text, pages });
} catch (error) {
  parentPort.postMessage({
    error: ["PDF_TOO_LONG", "PDF_NO_TEXT"].includes(error.message)
      ? error.message
      : error.name === "PasswordException"
        ? "PDF_ENCRYPTED"
        : "PDF_INVALID",
  });
}

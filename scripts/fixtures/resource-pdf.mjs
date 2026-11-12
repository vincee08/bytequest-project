// Synthetic classroom material only. No owner document is read by automated tests.
export function textPdf(
  text = "A router connects different IP networks. A switch connects devices on a local network. Inspect cables and verify connectivity with a LAN tester before troubleshooting software.",
) {
  const stream = (text.match(/.{1,100}/g) ?? [""])
    .map((line) => {
      const escaped = line
        .replaceAll("\\", "\\\\")
        .replaceAll("(", "\\(")
        .replaceAll(")", "\\)");
      return `BT /F1 12 Tf 50 700 Td (${escaped}) Tj ET`;
    })
    .join("\n");
  const objects = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    `<< /Length ${Buffer.byteLength(stream)} >>\nstream\n${stream}\nendstream`,
  ];
  return pdfFromObjects(objects);
}

export function manyPagesPdf(count = 51) {
  return pdfFromObjects([
    "<< /Type /Catalog /Pages 2 0 R >>",
    `<< /Type /Pages /Kids [${Array.from({ length: count }, (_, index) => `${index + 3} 0 R`).join(" ")}] /Count ${count} >>`,
    ...Array.from(
      { length: count },
      () => "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>",
    ),
  ]);
}

function pdfFromObjects(objects) {
  let pdf = "%PDF-1.4\n";
  const offsets = [0];
  for (const [index, object] of objects.entries()) {
    offsets.push(Buffer.byteLength(pdf));
    pdf += `${index + 1} 0 obj\n${object}\nendobj\n`;
  }
  const xref = Buffer.byteLength(pdf);
  pdf += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n${offsets
    .slice(1)
    .map((offset) => `${String(offset).padStart(10, "0")} 00000 n \n`)
    .join(
      "",
    )}trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return Buffer.from(pdf);
}

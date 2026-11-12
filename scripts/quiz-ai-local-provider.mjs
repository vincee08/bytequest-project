// Automated test double only; never presents itself as a real provider.
import http from "node:http";
let requests = 0;
http
  .createServer(async (req, res) => {
    res.setHeader("Content-Type", "application/json");
    if (req.method === "GET") {
      res.end(JSON.stringify({ requests }));
      return;
    }
    if (
      req.url !== "/chat/completions" ||
      req.headers.authorization !== "Bearer isolated-simulator-only"
    ) {
      res.writeHead(403).end("{}");
      return;
    }
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    const input = JSON.parse(Buffer.concat(chunks));
    const context = JSON.parse(input.messages[1].content);
    requests++;
    if (context.topic.includes("QA_INVALID_RESPONSE")) {
      res.end(JSON.stringify({ choices: [{ message: { content: "{}" } }] }));
      return;
    }
    if (context.topic.includes("QA_RATE_LIMIT")) {
      res.writeHead(429, { "Retry-After": "1" }).end("{}");
      return;
    }
    const properties =
      input.response_format.json_schema.schema.properties.questions.items
        .properties;
    const questions = Array.from({ length: context.item_count }, (_, index) => {
      const type =
        context.allowed_item_types[index % context.allowed_item_types.length];
      const choices =
        type === "multiple_choice" || type === "scenario_based"
          ? ["Router", "Switch", "Monitor"]
          : [];
      return {
        question: `${index + 1}. Which device connects different IP networks?`,
        type,
        choices,
        correctAnswer: type === "true_false" ? "true" : "Router",
        explanation: "A router forwards traffic between different IP networks.",
        competency: properties.competency.const,
        coc: properties.coc.const,
        learningOutcome: properties.learningOutcome.const,
      };
    });
    // Exercises concurrent-generation protection while the first request runs.
    await new Promise((resolve) => setTimeout(resolve, 800));
    res.end(
      JSON.stringify({
        choices: [{ message: { content: JSON.stringify({ questions }) } }],
      }),
    );
  })
  .listen(3007, "127.0.0.1", () =>
    console.log(
      "Isolated AI simulator on 127.0.0.1:3007; no external requests.",
    ),
  );

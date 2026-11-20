// Automated test double only; never presents itself as a real provider.
// Every prompt it returns starts with "Simulated draft" so a simulated question
// can never be mistaken for model output. It answers all three source modes:
// approved COC content and class resources (a fixed learningOutcome) and the
// curriculum (learningOutcome chosen from the allowed performance criteria),
// including scenario essays.
import http from "node:http";
let requests = 0;

function draftQuestion(type, label, topic) {
  if (type === "multiple_choice" || type === "scenario_based")
    return {
      question: `${label}: Which approach fits "${topic}"?`,
      choices: [
        "Follow the documented procedure",
        "Skip the safety check",
        "Guess the configuration",
      ],
      correctAnswer: "Follow the documented procedure",
    };
  if (type === "true_false")
    return {
      question: `${label}: Safety checks come before work on "${topic}".`,
      choices: [],
      correctAnswer: "true",
    };
  if (type === "identification")
    return {
      question: `${label}: Name the document that lists the steps for "${topic}".`,
      choices: [],
      correctAnswer: "procedure",
    };
  return {
    question: `${label}: Explain the steps you would take for "${topic}" and why.`,
    choices: [],
    correctAnswer: "States the steps in order and the safety precautions.",
    scenario: `A learner carries out "${topic}" at a workstation while the instructor observes the work.`,
    rubric: [
      { criterion: "Procedure", description: "States the steps in a workable order.", maxPoints: 5 },
      { criterion: "Safety", description: "Names the safety precautions and why they matter.", maxPoints: 5 },
    ],
    minWords: 30,
    maxWords: 200,
  };
}

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
    const outcomes = properties.learningOutcome.enum ?? [
      properties.learningOutcome.const,
    ];
    const essayFields = "scenario" in properties;
    const questions = Array.from({ length: context.item_count }, (_, index) => {
      const type =
        context.allowed_item_types[index % context.allowed_item_types.length];
      const draft = draftQuestion(
        type,
        `Simulated draft ${requests}.${index + 1}`,
        context.topic,
      );
      return {
        question: draft.question,
        type,
        choices: draft.choices,
        correctAnswer: draft.correctAnswer,
        explanation: "Simulated explanation: the documented procedure keeps the work safe and repeatable.",
        competency: properties.competency.const,
        coc: properties.coc.const,
        learningOutcome: outcomes[index % outcomes.length],
        ...(essayFields
          ? {
              scenario: draft.scenario ?? "",
              rubric: draft.rubric ?? [],
              minWords: draft.minWords ?? 0,
              maxWords: draft.maxWords ?? 0,
            }
          : {}),
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

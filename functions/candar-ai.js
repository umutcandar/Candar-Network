// Workers Free has a hard daily allowance. There is deliberately no paid fallback.
const MODEL = "@cf/qwen/qwen3-30b-a3b-fp8";

class AiServiceError extends Error {
  constructor(code) {
    super(code);
    this.code = code;
  }
}

async function generateAnswer(config, systemPrompt, prompt, fetchImpl = fetch) {
  if (!/^[a-f0-9]{32}$/.test(config?.accountId || "") || !config?.apiToken) {
    throw new AiServiceError("unavailable");
  }
  let response;
  try {
    response = await fetchImpl(
      `https://api.cloudflare.com/client/v4/accounts/${config.accountId}/ai/run/${MODEL}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${config.apiToken}` },
        body: JSON.stringify({
          messages: [
            { role: "system", content: systemPrompt + " /no_think" },
            { role: "user", content: prompt },
          ],
          max_tokens: 500,
          temperature: 0.3,
        }),
        signal: AbortSignal.timeout(25000),
      }
    );
  } catch (_) {
    throw new AiServiceError("unavailable");
  }
  if (response.status === 429) throw new AiServiceError("resource-exhausted");
  if (!response.ok) throw new AiServiceError("unavailable");
  let payload;
  try { payload = await response.json(); }
  catch (_) { throw new AiServiceError("unavailable"); }
  if (payload.success !== true) throw new AiServiceError("unavailable");
  const raw = payload.result?.response ?? payload.result?.choices?.[0]?.message?.content;
  if (typeof raw !== "string") throw new AiServiceError("unavailable");
  const answer = raw.replace(/<think>[\s\S]*?<\/think>/gi, "").trim();
  if (!answer || /<think>/i.test(answer)) throw new AiServiceError("unavailable");
  return answer;
}

module.exports = { generateAnswer, MODEL };

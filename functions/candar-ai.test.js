const assert = require("node:assert/strict");
const { generateAnswer, MODEL } = require("./candar-ai");
const config = { accountId: "a".repeat(32), apiToken: "fixture-not-a-real-token" };
let calls = 0;
const mock = (status, payload) => async (url, options) => {
  calls++;
  assert.equal(url, `https://api.cloudflare.com/client/v4/accounts/${config.accountId}/ai/run/${MODEL}`);
  const body = JSON.parse(options.body);
  assert.equal(body.max_tokens, 500);
  assert.equal(body.messages.length, 2);
  assert.equal(body.messages[1].content, "test question");
  assert.ok(options.signal);
  return { status, ok: status === 200, json: async () => payload };
};
(async () => {
  assert.equal(await generateAnswer(config, "system", "test question", mock(200, {success:true,result:{response:" Merhaba "}})), "Merhaba");
  assert.equal(await generateAnswer(config, "system", "test question", mock(200, {success:true,result:{choices:[{message:{content:"<think>private</think>Yanıt"}}]}})), "Yanıt");
  for (const [status,payload,code] of [
    [429, {}, "resource-exhausted"], [503, {}, "unavailable"], [401, {}, "unavailable"],
    [200, {success:false}, "unavailable"], [200, {success:true,result:{response:" "}}, "unavailable"],
    [200, {success:true,result:{response:"<think>unfinished"}}, "unavailable"],
  ]) {
    const before=calls;
    await assert.rejects(generateAnswer(config,"system","test question",mock(status,payload)), {code});
    assert.equal(calls,before+1,"no retry or paid provider fallback");
  }
  await assert.rejects(generateAnswer({},"system","test question",()=>{throw Error("must not fetch")}),{code:"unavailable"});
  await assert.rejects(generateAnswer(config,"system","test question",async()=>{throw Error("secret upstream error")}),{code:"unavailable",message:"unavailable"});
  await assert.rejects(generateAnswer(config,"system","test question",async()=>({ok:true,status:200,json:async()=>{throw Error("bad json")}})),{code:"unavailable"});
  console.log("Candar Ai: success, alternate response, quota, upstream errors, empty answers, timeout and no paid fallback checks passed.");
})().catch(error=>{console.error(error);process.exitCode=1;});

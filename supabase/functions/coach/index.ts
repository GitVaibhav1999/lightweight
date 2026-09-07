// The coach endpoint. The OpenRouter key lives here, never in the app binary.
// The client sends {kind, context, hint}; this signs the request, enforces per-user limits,
// and returns the model's JSON unchanged so the app's existing decoder keeps working.
import { createClient } from "jsr:@supabase/supabase-js@2";

const MODEL = "z-ai/glm-5.3-flash";
const DAILY_CALL_CAP = 40;

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });

  // caller identity comes from the JWT the app already holds; no key, no coach
  const authHeader = req.headers.get("Authorization") ?? "";
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return new Response("unauthorized", { status: 401 });

  const { kind, context, hint, system } = await req.json();
  if (!kind || !context || !system) return new Response("bad request", { status: 400 });

  // one row per call: the usage record doubles as the rate limit and the cost ledger
  const since = new Date(Date.now() - 86_400_000).toISOString();
  const { count } = await supabase.from("coach_calls")
    .select("id", { count: "exact", head: true })
    .eq("user_id", user.id).gte("created_at", since);
  if ((count ?? 0) >= DAILY_CALL_CAP) return new Response("daily limit reached", { status: 429 });

  const started = Date.now();
  const upstream = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${Deno.env.get("OPENROUTER_API_KEY")}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 9000,
      reasoning: { effort: "low" },
      messages: [
        { role: "system", content: system },
        { role: "user", content: `DATA: ${context}\nTASK: ${hint}` },
      ],
    }),
  });

  const body = await upstream.json();
  const text = body?.choices?.[0]?.message?.content ?? "";
  await supabase.from("coach_calls").insert({
    user_id: user.id, kind, model: MODEL,
    prompt_tokens: body?.usage?.prompt_tokens, completion_tokens: body?.usage?.completion_tokens,
    cost: body?.usage?.cost, ms: Date.now() - started,
    ok: text.length > 0,
  });

  if (!text) return new Response(JSON.stringify({ error: "empty completion" }), { status: 502 });
  return new Response(JSON.stringify({ text }), { headers: { "content-type": "application/json" } });
});

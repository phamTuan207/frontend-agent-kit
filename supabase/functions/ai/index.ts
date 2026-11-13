// supabase/functions/ai/index.ts — the AI endpoint (Deno Edge Function).
// FREE TIER ONLY. This function owns the Gemini key: it reads
// GEMINI_API_KEY from the function's secret (Deno.env) — never from
// code, never from the app bundle. The Convex action calls this
// function over HTTP; Convex never holds the key.
//
// Model: gemini-3.5-flash-lite (verified free of charge, no shutdown
// date). Over-limit fails with 429 — it never bills. NEVER link a
// billing account to the Gemini project or to Supabase.
//
// FALLBACK (documented, not wired): if Gemini fails, swap the fetch
// below to Groq's OpenAI-compatible endpoint with model
// "openai/gpt-oss-120b" (free tier: 30 RPM / 1,000 RPD / 8,000 TPM /
// 200,000 TPD; it answers 429 when a limit is exceeded). The Groq key
// would live in the same function secret as GROQ_API_KEY, and the
// request/response mapping is the same JSON shape. Do not wire the
// fallback on build day unless Gemini is actually down — one live path
// is easier to demo than two half-tested ones.
//
// Deploy (human, tonight): see README § "Tonight" — create the
// Supabase project, set the GEMINI_API_KEY secret, then:
//   supabase functions deploy ai --project-ref <REF>

const GEMINI_MODEL = 'gemini-3.5-flash-lite';
const GEMINI_URL = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;
const UPSTREAM_TIMEOUT_MS = 20000;
const MAX_PROMPT_CHARS = 4000;

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function errorResponse(
  code: string,
  message: string,
  status: number,
): Response {
  return jsonResponse({ error: { code, message } }, status);
}

Deno.serve(async (req: EdgeFunctionRequest) => {
  if (req.method !== 'POST') {
    return errorResponse('METHOD_NOT_ALLOWED', 'Use POST.', 405);
  }

  const apiKey = Deno.env.get('GEMINI_API_KEY');
  if (!apiKey) {
    // Fail loudly: a missing server secret is a deployment mistake,
    // and the Convex action surfaces this 503 as AI_UPSTREAM.
    return errorResponse(
      'CONFIG_MISSING',
      'GEMINI_API_KEY is not set as a Supabase function secret. Set it in the Supabase dashboard (Edge Functions → Secrets) and redeploy.',
      503,
    );
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return errorResponse('BAD_INPUT', 'Request body must be JSON.', 400);
  }

  const prompt =
    typeof body === 'object' && body !== null
      ? (body as { prompt?: unknown }).prompt
      : undefined;
  if (typeof prompt !== 'string' || prompt.trim().length === 0) {
    return errorResponse('BAD_INPUT', 'prompt must be a non-empty string.', 400);
  }
  if (prompt.length > MAX_PROMPT_CHARS) {
    return errorResponse(
      'BAD_INPUT',
      `prompt must be at most ${MAX_PROMPT_CHARS} characters.`,
      400,
    );
  }
  const maxTokens =
    typeof body === 'object' && body !== null
      ? (body as { max_tokens?: unknown }).max_tokens
      : undefined;
  const maxOutputTokens =
    typeof maxTokens === 'number' && maxTokens > 0 ? maxTokens : 800;

  let res: Awaited<ReturnType<typeof fetch>>;
  try {
    res = await fetch(GEMINI_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      },
      body: JSON.stringify({
        system_instruction: {
          parts: [
            {
              text: 'You answer with exactly 3 steps. Return ONLY a JSON object of the shape {"steps": [{"title": string, "detail": string}, {"title": string, "detail": string}, {"title": string, "detail": string}]}. No markdown, no extra keys.',
            },
          ],
        },
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: {
          maxOutputTokens,
          responseMimeType: 'application/json',
        },
      }),
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Upstream failed.';
    return errorResponse('AI_UPSTREAM', `Gemini unreachable: ${message}`, 502);
  }

  if (res.status === 429) {
    // Over-limit: propagate 429, never retry into a bill.
    return errorResponse(
      'RATE_LIMITED',
      'Gemini free-tier limit reached (429). Wait and retry; nothing was billed.',
      429,
    );
  }
  if (!res.ok) {
    return errorResponse(
      'AI_UPSTREAM',
      `Gemini returned HTTP ${res.status}.`,
      502,
    );
  }

  const data = (await res.json()) as {
    candidates?: {
      content?: { parts?: { text?: string }[] };
    }[];
  };
  const text = data.candidates?.[0]?.content?.parts?.[0]?.text;
  if (typeof text !== 'string' || text.length === 0) {
    return errorResponse('AI_BAD_RESPONSE', 'Gemini returned no text.', 502);
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    return errorResponse(
      'AI_BAD_RESPONSE',
      'Gemini returned text that is not JSON.',
      502,
    );
  }
  const steps =
    typeof parsed === 'object' && parsed !== null
      ? (parsed as { steps?: unknown }).steps
      : undefined;
  if (!Array.isArray(steps) || steps.length === 0) {
    return errorResponse(
      'AI_BAD_RESPONSE',
      'Gemini returned JSON without a steps array.',
      502,
    );
  }

  return jsonResponse({ steps, stubbed: false }, 200);
});

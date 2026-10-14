// Dify のチャット API をサーバー側で呼ぶ（API キーはブラウザに渡さない）
const DIFY_API_URL = process.env.DIFY_API_URL ?? "http://127.0.0.1:8080/v1";

export async function POST(req: Request) {
  const apiKey = process.env.DIFY_API_KEY;
  if (!apiKey) {
    return Response.json({ error: "DIFY_API_KEY が未設定です（.env.local に書いて再起動）" }, { status: 500 });
  }
  const { query, conversationId } = await req.json();
  const res = await fetch(`${DIFY_API_URL}/chat-messages`, {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      inputs: {},
      query,
      response_mode: "blocking",
      conversation_id: conversationId ?? "",
      user: "workshop-user",
    }),
  });
  const data = await res.json();
  if (!res.ok) {
    return Response.json({ error: data.message ?? "Dify でエラーが発生しました" }, { status: res.status });
  }
  return Response.json({ answer: data.answer, conversationId: data.conversation_id });
}

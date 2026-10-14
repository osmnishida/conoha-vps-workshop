"use client";

import { useState } from "react";

type Message = { role: "user" | "bot"; text: string };

export default function ChatPage() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState("");
  const [conversationId, setConversationId] = useState<string>();
  const [loading, setLoading] = useState(false);

  async function send(e: React.FormEvent) {
    e.preventDefault();
    const query = input.trim();
    if (!query || loading) return;
    setMessages((m) => [...m, { role: "user", text: query }]);
    setInput("");
    setLoading(true);
    // basePath は fetch に自動で付かないので /site を付ける
    const res = await fetch("/site/api/chat", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query, conversationId }),
    });
    const data = await res.json();
    setMessages((m) => [...m, { role: "bot", text: data.answer ?? `エラー：${data.error}` }]);
    if (data.conversationId) setConversationId(data.conversationId);
    setLoading(false);
  }

  return (
    <main style={{ fontFamily: "sans-serif", maxWidth: 640, margin: "2rem auto", padding: "0 1rem" }}>
      <h1>Dify チャット（Next.js から API 連携）</h1>
      <div style={{ minHeight: 200, border: "1px solid #ccc", borderRadius: 8, padding: 12, marginBottom: 12 }}>
        {messages.map((m, i) => (
          <p key={i} style={{ textAlign: m.role === "user" ? "right" : "left", whiteSpace: "pre-wrap" }}>
            <strong>{m.role === "user" ? "あなた" : "Dify"}：</strong>
            {m.text}
          </p>
        ))}
        {loading && <p>考え中…</p>}
      </div>
      <form onSubmit={send} style={{ display: "flex", gap: 8 }}>
        <input value={input} onChange={(e) => setInput(e.target.value)} placeholder="メッセージを入力"
          style={{ flex: 1, padding: 8 }} />
        <button type="submit" disabled={loading}>送信</button>
      </form>
    </main>
  );
}

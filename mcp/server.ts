#!/usr/bin/env bun
/**
 * Claude Peek MCP Channel Server
 *
 * Two-way channel:
 * 1. HTTP endpoint receives messages from Claude Peek app
 * 2. Pushes them into Claude Code via MCP channel notification
 * 3. Claude responds via the `reply` tool → forwarded back to the app
 *
 * Test: curl -X POST localhost:7778 -d '{"text":"hello from peek"}'
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

const PORT = Number(process.env.CLAUDE_PEEK_MCP_PORT ?? 7778);

const mcp = new Server(
  { name: "claude-peek", version: "0.1.0" },
  {
    capabilities: {
      experimental: { "claude/channel": {} },
      tools: {},
    },
    instructions: [
      'Messages from Claude Peek arrive as <channel source="claude-peek">.',
      "These are user messages sent from the Claude Peek notch UI.",
      "Reply using the reply tool. Keep replies concise.",
    ].join(" "),
  }
);

// Tool: reply — Claude calls this to send responses back to Peek
mcp.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "reply",
      description: "Send a reply to the user via Claude Peek notch UI",
      inputSchema: {
        type: "object" as const,
        properties: {
          text: { type: "string", description: "Reply text" },
        },
        required: ["text"],
      },
    },
  ],
}));

mcp.setRequestHandler(CallToolRequestSchema, async (req) => {
  if (req.params.name === "reply") {
    const text = (req.params.arguments as Record<string, string>)?.text ?? "";
    console.error(`[claude-peek] Reply: ${text.slice(0, 200)}`);
    // TODO: forward to Claude Peek app via socket
    return { content: [{ type: "text" as const, text: "sent" }] };
  }
  return {
    content: [
      { type: "text" as const, text: `Unknown tool: ${req.params.name}` },
    ],
    isError: true,
  };
});

// Connect MCP via stdio
const transport = new StdioServerTransport();
await mcp.connect(transport);
console.error(`[claude-peek] MCP channel server connected`);

// HTTP endpoint for receiving messages from Claude Peek app
Bun.serve({
  port: PORT,
  hostname: "127.0.0.1",
  async fetch(req) {
    if (req.method !== "POST") {
      return new Response("POST only", { status: 405 });
    }

    try {
      const body = await req.json();
      const text = body.text ?? body.message ?? "";
      if (!text) {
        return new Response("missing text", { status: 400 });
      }

      console.error(`[claude-peek] Pushing message: ${text.slice(0, 100)}`);

      await mcp.notification({
        method: "notifications/claude/channel",
        params: {
          content: text,
          meta: {
            chat_id: body.session_id ?? "peek",
            message_id: String(Date.now()),
            user: "user",
            ts: new Date().toISOString(),
          },
        },
      });

      return new Response(JSON.stringify({ ok: true }), {
        headers: { "Content-Type": "application/json" },
      });
    } catch (e) {
      console.error(`[claude-peek] Error: ${e}`);
      return new Response("error", { status: 500 });
    }
  },
});

console.error(`[claude-peek] HTTP listening on http://127.0.0.1:${PORT}`);

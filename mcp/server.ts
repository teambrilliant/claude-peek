#!/usr/bin/env bun
/**
 * Claude Peek MCP Channel Server
 *
 * Each Claude Code session spawns its own instance.
 * Binds to a random port, registers with Claude Peek app via socket.
 *
 * Test: curl -X POST localhost:<port> -d '{"text":"hello"}'
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { connect } from "net";

const SOCKET_PATH = "/tmp/claude-peek.sock";

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
    return { content: [{ type: "text" as const, text: "sent" }] };
  }
  return {
    content: [
      { type: "text" as const, text: `Unknown tool: ${req.params.name}` },
    ],
    isError: true,
  };
});

const transport = new StdioServerTransport();
await mcp.connect(transport);
console.error(`[claude-peek] MCP channel server connected`);

// Bind to port 0 — OS assigns a free port
const httpServer = Bun.serve({
  port: 0,
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

const actualPort = httpServer.port;
console.error(`[claude-peek] HTTP listening on http://127.0.0.1:${actualPort}`);

// Register this channel's port with Claude Peek app via the hook socket
function registerPort() {
  try {
    const client = connect(SOCKET_PATH, () => {
      const registration = JSON.stringify({
        event: "ChannelRegistration",
        port: actualPort,
        pid: process.ppid,
        session_id: "unknown",
        cwd: process.cwd(),
        status: "channel_ready",
      });
      client.write(registration);
      client.end();
      console.error(`[claude-peek] Registered port ${actualPort} with Claude Peek`);
    });
    client.on("error", () => {
      console.error(`[claude-peek] Could not register with Claude Peek (socket not available)`);
    });
  } catch {
    console.error(`[claude-peek] Registration failed`);
  }
}

registerPort();

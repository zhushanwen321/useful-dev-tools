#!/usr/bin/env node
// CDP (Chrome DevTools Protocol) WebSocket client
// Node.js v21+ required (built-in WebSocket)
//
// Usage:
//   node cdp.js <wsUrl> <CDP_Method> [paramsJson]   — raw CDP command
//   node cdp.js <wsUrl> navigate <url>               — navigate and wait for load

const [,, wsUrl, command, ...args] = process.argv;
let msgId = 0;

function cdp(ws, method, params = {}) {
  const id = ++msgId;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('CDP timeout (15s)')), 15000);
    const handler = (data) => {
      const msg = JSON.parse(data.toString());
      if (msg.id === id) {
        clearTimeout(timer);
        ws.off('message', handler);
        resolve(msg);
      }
    };
    ws.on('message', handler);
    ws.send(JSON.stringify({ id, method, params }));
  });
}

async function main() {
  if (!wsUrl || !command) {
    console.error('Usage: node cdp.js <wsUrl> <method|navigate> [paramsJson|url]');
    process.exit(1);
  }

  const ws = new WebSocket(wsUrl);
  await new Promise((res, rej) => {
    ws.on('open', res);
    ws.on('error', rej);
  });

  let result;

  if (command === 'navigate') {
    await cdp(ws, 'Page.enable');
    result = await cdp(ws, 'Page.navigate', { url: args[0] });
    await new Promise((res) => {
      const timer = setTimeout(res, 10000);
      const handler = (data) => {
        try {
          if (JSON.parse(data.toString()).method === 'Page.loadEventFired') {
            clearTimeout(timer);
            ws.off('message', handler);
            res();
          }
        } catch {}
      };
      ws.on('message', handler);
    });
  } else {
    const params = args[0] ? JSON.parse(args[0]) : {};
    result = await cdp(ws, command, params);
  }

  console.log(JSON.stringify(result, null, 2));
  ws.close();
}

main().catch((e) => {
  console.error(JSON.stringify({ error: e.message }));
  process.exit(1);
});

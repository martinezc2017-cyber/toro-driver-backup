import websocket
import json
import time
import sys

# Connect to Chrome DevTools
ws_url = "ws://localhost:55870/devtools/page/2704549A2C82178C02CE3BB1F2525B59"
ws = websocket.create_connection(ws_url, timeout=10)

# Enable Console
ws.send(json.dumps({"id": 1, "method": "Console.enable"}))
ws.send(json.dumps({"id": 2, "method": "Runtime.enable"}))
ws.send(json.dumps({"id": 3, "method": "Log.enable"}))

# Get existing console messages by evaluating something
ws.send(json.dumps({"id": 4, "method": "Runtime.evaluate", "params": {
    "expression": """
    console.log('=== KPI CHECK ===');
    // Try to access kpi repo through window
    if (window.__kpiData) {
        console.log('Found kpiData', JSON.stringify(window.__kpiData));
    }
    console.log('Check complete');
    """,
    "objectGroup": "console",
    "includeCommandLineAPI": True
}}))

# Collect messages for 5 seconds
timeout = time.time() + 5
collected = []
while time.time() < timeout:
    try:
        ws.settimeout(0.5)
        msg = json.loads(ws.recv())
        if msg.get('method') in ['Console.messageAdded', 'Runtime.consoleAPICalled', 'Log.entryAdded']:
            # Extract the message
            if msg['method'] == 'Runtime.consoleAPICalled':
                for arg in msg['params'].get('args', []):
                    if 'value' in arg:
                        collected.append(str(arg['value']))
            elif msg['method'] == 'Console.messageAdded':
                collected.append(msg['params']['message'].get('text', ''))
            elif msg['method'] == 'Log.entryAdded':
                collected.append(msg['params']['entry'].get('text', ''))
    except websocket.TimeoutError:
        continue
    except Exception as e:
        collected.append(f"Error: {e}")

ws.close()

print("=== CONSOLE LOGS ===")
for line in collected:
    print(line)

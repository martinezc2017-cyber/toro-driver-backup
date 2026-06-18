import json
import urllib.request
import time

# Use Chrome DevTools Protocol via HTTP to evaluate JavaScript
resp = urllib.request.urlopen("http://localhost:58720/json")
targets = json.loads(resp.read())
print("Available targets:")
for t in targets:
    print(f"  {t.get('title', 'N/A')}: {t.get('url', 'N/A')}")

# Find the TORO Admin target
ws_url = None
for t in targets:
    if 'TORO' in t.get('title', '') or 'admin' in t.get('url', '').lower():
        ws_url = t.get('webSocketDebuggerUrl')
        print(f"\nFound TORO Admin target: {ws_url}")

if ws_url:
    try:
        import websocket
        ws = websocket.create_connection(ws_url, timeout=10)
        
        # Enable console
        ws.send(json.dumps({"id": 0, "method": "Console.enable"}))
        ws.send(json.dumps({"id": 1, "method": "Runtime.enable"}))
        ws.send(json.dumps({"id": 2, "method": "Log.enable"}))
        time.sleep(0.2)
        
        # Execute KPI check
        ws.send(json.dumps({
            "id": 3,
            "method": "Runtime.evaluate",
            "params": {
                "expression": """
                console.log('=== KPI CHECK FROM CHROME DEVTOOLS ===');
                const text = document.body.innerText;
                const lines = text.split('\\n').filter(l => l.includes('$') || l.toLowerCase().includes('gross') || l.toLowerCase().includes('plat') || l.toLowerCase().includes('drv') || l.includes('VIAJES'));
                lines.forEach(l => console.log(l));
                console.log('KPI check complete');
                """,
                "returnByValue": True
            }
        }))
        
        # Collect messages for 3 seconds
        timeout = time.time() + 3
        collected = []
        while time.time() < timeout:
            try:
                ws.settimeout(0.3)
                msg = json.loads(ws.recv())
                if msg.get('method') == 'Runtime.consoleAPICalled':
                    for arg in msg['params'].get('args', []):
                        if 'value' in arg:
                            collected.append(str(arg['value']))
                elif msg.get('method') == 'Log.entryAdded':
                    collected.append(msg['params']['entry'].get('text', ''))
            except websocket.TimeoutError:
                continue
            except Exception as e:
                pass
        
        ws.close()
        
        print("\n=== DASHBOARD KPI VALUES ===")
        for line in collected:
            print(line)
        
    except ImportError:
        print("websocket module not installed locally")
    except Exception as e:
        print(f"Error: {e}")
else:
    print("Could not find TORO Admin target")

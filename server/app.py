

from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path
from typing import Any, List

import uvicorn
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware


BASE = Path(__file__).parent
CONFIG_FILE = BASE / "config.json"
AUDIT_FILE  = BASE / "audit.json"


DEFAULT_CONFIG: dict = {
    "flags": {
        "dark_mode_beta": {
            "enabled": True,
            "rollout": 100,
            "groups": ["everyone"]
        },
        "new_checkout_flow": {
            "enabled": True,
            "rollout": 20,
            "groups": ["beta"]
        },
        "ai_recommendations": {
            "enabled": True,
            "rollout": 10,
            "groups": ["everyone"]
        }
    },
    "configs": {
        "welcome_message": "Hello, World!",
        "max_login_attempts": 5
    }
}

if not CONFIG_FILE.exists():
    CONFIG_FILE.write_text(json.dumps(DEFAULT_CONFIG, indent=2))
if not AUDIT_FILE.exists():
    AUDIT_FILE.write_text("[]")



def load_config() -> dict:
    return json.loads(CONFIG_FILE.read_text())


def save_config(config: dict) -> None:
    CONFIG_FILE.write_text(json.dumps(config, indent=2))


def append_audit(action: str, target: str, old: Any, new: Any) -> None:
    try:
        entries: list = json.loads(AUDIT_FILE.read_text())
    except Exception:
        entries = []
    entries.append({
        "time":   datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "action": action,
        "target": target,
        "old":    old,
        "new":    new,
    })
    AUDIT_FILE.write_text(json.dumps(entries[-100:], indent=2))



class ConnectionManager:
    def __init__(self) -> None:
        self._connections: List[WebSocket] = []

    async def connect(self, ws: WebSocket) -> None:
        await ws.accept()
        self._connections.append(ws)

    def disconnect(self, ws: WebSocket) -> None:
        self._connections.discard if hasattr(self._connections, "discard") else None
        if ws in self._connections:
            self._connections.remove(ws)

    async def broadcast(self, payload: dict) -> None:
        dead: list[WebSocket] = []
        for ws in list(self._connections):
            try:
                await ws.send_json(payload)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self.disconnect(ws)


manager = ConnectionManager()


app = FastAPI(title="Feature Flag Engine", version="2.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)



@app.get("/config")
def get_config() -> dict:
    """Return full config snapshot."""
    return load_config()


@app.patch("/flag/{name}")
async def patch_flag(name: str, body: dict) -> dict:
    """
    Update a flag.  Body may contain any subset of:
      { "enabled": bool, "rollout": int 1-100, "groups": [str] }
    Creates the flag if it doesn't exist.
    """
    config = load_config()
    flags  = config["flags"]

    if name not in flags:
        flags[name] = {"enabled": False, "rollout": 100, "groups": ["everyone"]}

    old = dict(flags[name])

    allowed = {"enabled", "rollout", "groups"}
    for k, v in body.items():
        if k in allowed:
            if k == "rollout":
                v = max(1, min(100, int(v)))
            flags[name][k] = v

    save_config(config)
    append_audit("flag_update", name, old, flags[name])
    await manager.broadcast({"type": "config_update", "data": config})
    return flags[name]


@app.patch("/config/{key}")
async def patch_config(key: str, body: dict) -> dict:
    """
    Update a remote-config value.
    Body: { "value": <str | int | float> }
    """
    config = load_config()
    old    = config["configs"].get(key)
    value  = body.get("value", "")

    config["configs"][key] = value
    save_config(config)
    append_audit("config_update", key, old, value)
    await manager.broadcast({"type": "config_update", "data": config})
    return {"key": key, "value": value}


@app.post("/reload")
async def reload_config() -> dict:
    """Re-read config from disk and broadcast to all WebSocket clients."""
    config = load_config()
    await manager.broadcast({"type": "config_update", "data": config})
    return {"status": "reloaded", "connections": len(manager._connections)}


@app.get("/audit")
def get_audit() -> list:
    """Return last 100 audit log entries."""
    try:
        return json.loads(AUDIT_FILE.read_text())
    except Exception:
        return []



@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket) -> None:
    await manager.connect(ws)
    try:
        await ws.send_json({"type": "config_update", "data": load_config()})
        while True:
            await ws.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(ws)
    except Exception:
        manager.disconnect(ws)



if __name__ == "__main__":
    print("[Server] Feature Flag Engine running on http://localhost:8080")
    print("[Server] WebSocket available at ws://localhost:8080/ws")
    print("[Server] API docs at http://localhost:8080/docs")
    uvicorn.run(app, host="0.0.0.0", port=8080, log_level="warning")

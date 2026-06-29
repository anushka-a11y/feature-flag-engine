"""
Feature Flag & Config Manager — Textual TUI Dashboard
======================================================
Keyboard bindings
  Space       Toggle selected flag ON / OFF
  Enter       Edit rule (rollout %, groups) for selected flag
              OR edit value for selected config
  Tab         Move focus between Flags table and Configs table
  Shift+Tab   Reverse tab
  R           Reload config from disk (+ broadcast via POST /reload)
  Q           Quit
"""

import json
import threading
from pathlib import Path

import requests
from textual import events
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Container, Horizontal, Vertical
from textual.screen import ModalScreen
from textual.widgets import (
    Button,
    DataTable,
    Footer,
    Header,
    Input,
    Label,
    Static,
)
from rich.text import Text

SERVER_URL  = "http://localhost:8080"
CONFIG_FILE = Path(__file__).parent / "config.json"


# ── Helpers ───────────────────────────────────────────────────────────────────

def load_config() -> dict:
    with open(CONFIG_FILE, "r") as f:
        return json.load(f)


def patch_flag(name: str, payload: dict) -> None:
    """PATCH /flag/<name> — update one flag's fields."""
    try:
        requests.patch(f"{SERVER_URL}/flag/{name}", json=payload, timeout=2)
    except Exception:
        pass


def patch_config(key: str, value) -> None:
    """PATCH /config/<key> — update one remote-config value."""
    try:
        requests.patch(f"{SERVER_URL}/config/{key}", json={"value": value}, timeout=2)
    except Exception:
        pass


def reload_server() -> None:
    """POST /reload — tell server to broadcast current disk state."""
    try:
        requests.post(f"{SERVER_URL}/reload", timeout=2)
    except Exception:
        pass


# ── Edit Groups / Rollout Modal ───────────────────────────────────────────────

class EditFlagModal(ModalScreen):
    """Pop-up to edit a flag's rollout % and groups."""

    CSS = """
    EditFlagModal { align: center middle; }
    #dialog {
        padding: 1 2; width: 64; height: auto;
        border: thick $warning; background: $surface;
    }
    #dialog Label  { margin-bottom: 1; }
    #dialog Input  { margin-bottom: 1; }
    #btn-row { height: auto; }
    #btn-row Button { margin-right: 1; }
    """

    def __init__(self, flag_id: str, current: dict):
        super().__init__()
        self.flag_id = flag_id
        self.current = current

    def compose(self) -> ComposeResult:
        rollout = str(self.current.get("rollout", 100))
        groups  = ",".join(self.current.get("groups", ["everyone"]))
        with Container(id="dialog"):
            yield Label(f"Editing flag: [bold]{self.flag_id}[/bold]")
            yield Label("Rollout % (1–100):")
            yield Input(value=rollout, id="rollout-input")
            yield Label("Groups (comma-separated, e.g. everyone,beta,staff):")
            yield Input(value=groups, id="groups-input")
            with Horizontal(id="btn-row"):
                yield Button("Save  [Enter]", variant="success", id="save")
                yield Button("Cancel  [Esc]", variant="default",  id="cancel")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "save":
            self._dismiss_save()
        else:
            self.dismiss(None)

    def on_key(self, event: events.Key) -> None:
        if event.key == "enter":
            self._dismiss_save()
        elif event.key == "escape":
            self.dismiss(None)

    def _dismiss_save(self) -> None:
        rollout_raw = self.query_one("#rollout-input", Input).value
        groups_raw  = self.query_one("#groups-input",  Input).value
        try:
            rollout = max(1, min(100, int(rollout_raw)))
        except ValueError:
            rollout = 100
        groups = [g.strip() for g in groups_raw.split(",") if g.strip()]
        if not groups:
            groups = ["everyone"]
        self.dismiss({"rollout": rollout, "groups": groups})


# ── Edit Config Modal ─────────────────────────────────────────────────────────

class EditConfigModal(ModalScreen):
    """Pop-up to edit a remote-config value."""

    CSS = """
    EditConfigModal { align: center middle; }
    #dialog {
        padding: 1 2; width: 60; height: auto;
        border: thick $accent; background: $surface;
    }
    #dialog Label  { margin-bottom: 1; }
    #dialog Input  { margin-bottom: 1; }
    #btn-row { height: auto; }
    #btn-row Button { margin-right: 1; }
    """

    def __init__(self, key: str, current_value):
        super().__init__()
        self.config_key    = key
        self.current_value = str(current_value)

    def compose(self) -> ComposeResult:
        with Container(id="dialog"):
            yield Label(f"Editing config: [bold]{self.config_key}[/bold]")
            yield Input(value=self.current_value, id="value-input", placeholder="New value")
            with Horizontal(id="btn-row"):
                yield Button("Save  [Enter]", variant="success", id="save")
                yield Button("Cancel  [Esc]", variant="default",  id="cancel")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "save":
            self.dismiss(self.query_one("#value-input", Input).value)
        else:
            self.dismiss(None)

    def on_key(self, event: events.Key) -> None:
        if event.key == "enter":
            self.dismiss(self.query_one("#value-input", Input).value)
        elif event.key == "escape":
            self.dismiss(None)


# ── Main App ──────────────────────────────────────────────────────────────────

class FlagManagerApp(App):

    CSS = """
    Screen { background: $background; }

    #status-bar {
        height: 1; padding: 0 1;
        background: $primary-darken-3; color: $text-muted;
    }
    .section-title {
        height: 1; padding: 0 1;
        background: $accent-darken-2; color: $text; text-style: bold;
    }
    DataTable {
        height: auto; max-height: 14;
        border: none; margin: 0 0 1 0;
    }
    .hint {
        height: 1; padding: 0 1;
        color: $text-muted; background: $surface-darken-1;
    }
    """

    BINDINGS = [
        Binding("q",         "quit",          "Quit"),
        Binding("space",     "toggle_flag",   "Toggle Flag"),
        Binding("enter",     "edit_selected", "Edit"),
        Binding("tab",       "focus_next",    "Next Table",  show=False),
        Binding("shift+tab", "focus_previous","Prev Table",  show=False),
        Binding("r",         "reload",        "Reload"),
    ]

    TITLE = "🚀  Feature Flag & Config Manager"

    def __init__(self):
        super().__init__()
        self._config          = load_config()
        self._status          = f"Ready  —  server: {SERVER_URL}"
        self._focused_table   = "flags"

    # ── Layout ────────────────────────────────────────────────────────────────

    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        with Vertical():
            yield Static(self._status, id="status-bar")
            yield Label("  ACTIVE FLAGS", classes="section-title")
            yield DataTable(id="flags-table", cursor_type="row")
            yield Label("  CONFIG VARIABLES", classes="section-title")
            yield DataTable(id="configs-table", cursor_type="row")
            yield Static(
                "  [Space] Toggle  │  [Enter] Edit Rollout/Groups or Config"
                "  │  [R] Reload  │  [Q] Quit",
                classes="hint"
            )
        yield Footer()

    def on_mount(self) -> None:
        self._build_flags_table()
        self._build_configs_table()
        self.query_one("#flags-table", DataTable).focus()

    # ── Table builders ────────────────────────────────────────────────────────

    def _build_flags_table(self) -> None:
        t: DataTable = self.query_one("#flags-table", DataTable)
        t.clear(columns=True)
        t.add_columns("#", "Flag ID", "Status", "Rollout", "Groups")
        for i, (flag_id, flag) in enumerate(self._config["flags"].items(), 1):
            status = (
                Text("● ON ", style="bold green")
                if flag.get("enabled", False)
                else Text("○ OFF", style="dim red")
            )
            groups = ", ".join(flag.get("groups", ["everyone"]))
            t.add_row(
                str(i),
                flag_id,
                status,
                f"{flag.get('rollout', 100)}%",
                groups,
                key=flag_id,
            )

    def _build_configs_table(self) -> None:
        t: DataTable = self.query_one("#configs-table", DataTable)
        t.clear(columns=True)
        t.add_columns("#", "Key", "Value")
        for i, (key, value) in enumerate(self._config["configs"].items(), 1):
            t.add_row(str(i), key, str(value), key=key)

    def _refresh_all(self) -> None:
        self._build_flags_table()
        self._build_configs_table()

    def _set_status(self, msg: str) -> None:
        self._status = msg
        self.query_one("#status-bar", Static).update(msg)

    # ── Focus tracking ────────────────────────────────────────────────────────

    def on_data_table_row_highlighted(self, event: DataTable.RowHighlighted) -> None:
        self._focused_table = event.data_table.id.replace("-table", "")

    def on_focus(self, event: events.Focus) -> None:
        widget = event.widget
        if hasattr(widget, "id") and widget.id in ("flags-table", "configs-table"):
            self._focused_table = widget.id.replace("-table", "")

    # ── Actions ───────────────────────────────────────────────────────────────

    def action_toggle_flag(self) -> None:
        if self._focused_table != "flags":
            self._set_status("⚠  Select a flag row first (Tab to switch)")
            return
        t: DataTable = self.query_one("#flags-table", DataTable)
        if t.cursor_row is None:
            return
        flag_id = t.get_row_at(t.cursor_row)[1]
        flag    = self._config["flags"].get(flag_id)
        if not flag:
            return
        flag["enabled"] = not flag["enabled"]
        state = "ON" if flag["enabled"] else "OFF"
        patch_flag(flag_id, {"enabled": flag["enabled"]})
        self._set_status(f"✔  '{flag_id}' toggled → {state}")
        self._refresh_all()
        t.focus()
        self.call_after_refresh(lambda: t.move_cursor(row=t.cursor_row))

    def action_edit_selected(self) -> None:
        if self._focused_table == "flags":
            self._open_edit_flag_modal()
        else:
            self._open_edit_config_modal()

    def _open_edit_flag_modal(self) -> None:
        t: DataTable = self.query_one("#flags-table", DataTable)
        if t.cursor_row is None:
            return
        flag_id = t.get_row_at(t.cursor_row)[1]
        flag    = self._config["flags"].get(flag_id)
        if not flag:
            return

        def handle(result):
            if result:
                flag.update(result)
                patch_flag(flag_id, result)
                self._refresh_all()
                self._set_status(
                    f"✔  '{flag_id}' → rollout={result['rollout']}%  "
                    f"groups={result['groups']}"
                )

        self.push_screen(EditFlagModal(flag_id, flag), handle)

    def _open_edit_config_modal(self) -> None:
        t: DataTable = self.query_one("#configs-table", DataTable)
        if t.cursor_row is None:
            return
        key = t.get_row_at(t.cursor_row)[1]
        current_value = self._config["configs"].get(key, "")

        def handle(new_value):
            if new_value is not None:
                # Attempt numeric coercion
                try:
                    coerced: int | float | str = int(new_value)
                except ValueError:
                    try:
                        coerced = float(new_value)
                    except ValueError:
                        coerced = new_value
                self._config["configs"][key] = coerced
                patch_config(key, coerced)
                self._refresh_all()
                self._set_status(f"✔  Config '{key}' → {coerced}")

        self.push_screen(EditConfigModal(key, current_value), handle)

    def action_reload(self) -> None:
        self._config = load_config()
        self._refresh_all()
        reload_server()
        self._set_status("🔄  Reloaded from disk + broadcast to clients")


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import subprocess, sys, time

    # Start FastAPI server in background
    server_proc = subprocess.Popen(
        [sys.executable, str(Path(__file__).parent / "app.py")],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    time.sleep(1)  # give server time to bind

    try:
        FlagManagerApp().run()
    finally:
        server_proc.terminate()
import json
import threading
import requests
from pathlib import Path
from textual.app import App, ComposeResult
from textual.widgets import (
    Header, Footer, DataTable, Label,
    Input, Button, Static
)
from textual.containers import Vertical, Horizontal, Container
from textual.screen import ModalScreen
from textual.binding import Binding
from textual import events
from rich.text import Text

SERVER_URL = "http://localhost:8080"
FLAGS_FILE = Path(__file__).parent / "flags.json"


# ── Helper ────────────────────────────────────────────────────────────────────

def load_flags():
    with open(FLAGS_FILE, "r") as f:
        return json.load(f)


def save_and_push(data):
    """Write to disk and notify the server."""
    with open(FLAGS_FILE, "w") as f:
        json.dump(data, f, indent=2)
    try:
        requests.post(f"{SERVER_URL}/flags", json=data, timeout=1)
    except Exception:
        pass  # server might not be running yet; disk write still succeeds


# ── Edit Config Modal ─────────────────────────────────────────────────────────

class EditConfigModal(ModalScreen):
    """Pop-up for editing a config value."""

    CSS = """
    EditConfigModal {
        align: center middle;
    }
    #dialog {
        padding: 1 2;
        width: 60;
        height: auto;
        border: thick $accent;
        background: $surface;
    }
    #dialog Label { margin-bottom: 1; }
    #dialog Input  { margin-bottom: 1; }
    #btn-row { height: auto; }
    #btn-row Button { margin-right: 1; }
    """

    def __init__(self, key: str, current_value):
        super().__init__()
        self.config_key = key
        self.current_value = str(current_value)

    def compose(self) -> ComposeResult:
        with Container(id="dialog"):
            yield Label(f"Editing: [bold]{self.config_key}[/bold]")
            yield Input(value=self.current_value, id="value-input", placeholder="New value")
            with Horizontal(id="btn-row"):
                yield Button("Save  [Enter]", variant="success", id="save")
                yield Button("Cancel  [Esc]", variant="default", id="cancel")

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


# ── Edit Rule Modal ───────────────────────────────────────────────────────────

class EditRuleModal(ModalScreen):
    """Pop-up for editing a flag's targeting rule."""

    CSS = """
    EditRuleModal {
        align: center middle;
    }
    #dialog {
        padding: 1 2;
        width: 60;
        height: auto;
        border: thick $warning;
        background: $surface;
    }
    #dialog Label  { margin-bottom: 1; }
    #dialog Input  { margin-bottom: 1; }
    #btn-row { height: auto; }
    #btn-row Button { margin-right: 1; }
    """

    def __init__(self, flag_id: str, current_rule: str, current_rollout: int):
        super().__init__()
        self.flag_id = flag_id
        self.current_rule = current_rule
        self.current_rollout = str(current_rollout)

    def compose(self) -> ComposeResult:
        with Container(id="dialog"):
            yield Label(f"Editing rule for: [bold]{self.flag_id}[/bold]")
            yield Label("Targeting rule (e.g. Everyone / Beta Users Only):")
            yield Input(value=self.current_rule, id="rule-input")
            yield Label("Rollout percentage (1–100):")
            yield Input(value=self.current_rollout, id="rollout-input")
            with Horizontal(id="btn-row"):
                yield Button("Save  [Enter]", variant="success", id="save")
                yield Button("Cancel  [Esc]", variant="default", id="cancel")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "save":
            rule = self.query_one("#rule-input", Input).value
            rollout_raw = self.query_one("#rollout-input", Input).value
            try:
                rollout = max(1, min(100, int(rollout_raw)))
            except ValueError:
                rollout = 100
            self.dismiss({"rule": rule, "rollout": rollout})
        else:
            self.dismiss(None)

    def on_key(self, event: events.Key) -> None:
        if event.key == "escape":
            self.dismiss(None)


# ── Main App ──────────────────────────────────────────────────────────────────

class FlagManagerApp(App):

    CSS = """
    Screen {
        background: $background;
    }

    /* ── Status bar ── */
    #status-bar {
        height: 1;
        padding: 0 1;
        background: $primary-darken-3;
        color: $text-muted;
    }

    /* ── Section headings ── */
    .section-title {
        height: 1;
        padding: 0 1;
        background: $accent-darken-2;
        color: $text;
        text-style: bold;
    }

    /* ── Tables ── */
    DataTable {
        height: auto;
        max-height: 14;
        border: none;
        margin: 0 0 1 0;
    }

    /* ── Hint row ── */
    .hint {
        height: 1;
        padding: 0 1;
        color: $text-muted;
        background: $surface-darken-1;
    }
    """

    BINDINGS = [
        Binding("q", "quit", "Quit"),
        Binding("space", "toggle_flag", "Toggle Flag"),
        Binding("enter", "edit_selected", "Edit Rule / Config"),
        Binding("tab", "focus_next", "Switch Table", show=False),
        Binding("shift+tab", "focus_previous", "Switch Table", show=False),
        Binding("r", "reload", "Reload from disk"),
    ]

    TITLE = "🚀  Feature Flag & Config Manager"

    def __init__(self):
        super().__init__()
        self._data = load_flags()
        self._status = "Ready  —  server: http://localhost:8080/flags"
        self._focused_table = "flags"   # "flags" | "configs"

    # ── Layout ───────────────────────────────────────────────────────────────

    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)

        with Vertical():
            yield Static(self._status, id="status-bar")

            yield Label("  ACTIVE FLAGS", classes="section-title")
            yield DataTable(id="flags-table", cursor_type="row")

            yield Label("  CONFIG VARIABLES", classes="section-title")
            yield DataTable(id="configs-table", cursor_type="row")

            yield Static(
                "  [Space] Toggle Flag  │  [Enter] Edit Rule/Config  │"
                "  [R] Reload  │  [Q] Quit",
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
        t.add_columns("#", "Flag ID", "Status", "Rule", "Rollout")
        for i, flag in enumerate(self._data["flags"], 1):
            status = (
                Text("● ON ", style="bold green")
                if flag["enabled"]
                else Text("○ OFF", style="dim red")
            )
            rollout = f"{flag.get('rollout_percentage', 100)}%"
            t.add_row(
                str(i),
                flag["id"],
                status,
                flag.get("rule", "Everyone"),
                rollout,
                key=flag["id"],
            )

    def _build_configs_table(self) -> None:
        t: DataTable = self.query_one("#configs-table", DataTable)
        t.clear(columns=True)
        t.add_columns("#", "Key", "Value", "Type")
        for i, cfg in enumerate(self._data["configs"], 1):
            t.add_row(
                str(i),
                cfg["key"],
                str(cfg["value"]),
                cfg["type"],
                key=cfg["key"],
            )

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
            self._set_status("⚠  Select a flag row first (Tab to switch tables)")
            return
        t: DataTable = self.query_one("#flags-table", DataTable)
        if t.cursor_row is None:
            return
        row_key = t.get_row_at(t.cursor_row)[1]   # column 1 = flag id
        for flag in self._data["flags"]:
            if flag["id"] == row_key:
                flag["enabled"] = not flag["enabled"]
                state = "ON" if flag["enabled"] else "OFF"
                self._set_status(f"✔  '{row_key}' toggled → {state}")
                break
        save_and_push(self._data)
        self._refresh_all()
        # restore cursor
        t.focus()
        self.call_after_refresh(lambda: t.move_cursor(row=t.cursor_row))

    def action_edit_selected(self) -> None:
        if self._focused_table == "flags":
            self._open_edit_rule_modal()
        else:
            self._open_edit_config_modal()

    def _open_edit_rule_modal(self) -> None:
        t: DataTable = self.query_one("#flags-table", DataTable)
        if t.cursor_row is None:
            return
        row = t.get_row_at(t.cursor_row)
        flag_id = row[1]
        flag = next((f for f in self._data["flags"] if f["id"] == flag_id), None)
        if not flag:
            return

        def handle_result(result):
            if result:
                flag["rule"] = result["rule"]
                flag["rollout_percentage"] = result["rollout"]
                save_and_push(self._data)
                self._refresh_all()
                self._set_status(f"✔  Rule updated for '{flag_id}'")

        self.push_screen(
            EditRuleModal(flag_id, flag.get("rule", "Everyone"),
                          flag.get("rollout_percentage", 100)),
            handle_result
        )

    def _open_edit_config_modal(self) -> None:
        t: DataTable = self.query_one("#configs-table", DataTable)
        if t.cursor_row is None:
            return
        row = t.get_row_at(t.cursor_row)
        cfg_key = row[1]
        cfg = next((c for c in self._data["configs"] if c["key"] == cfg_key), None)
        if not cfg:
            return

        def handle_result(new_value):
            if new_value is not None:
                cfg["value"] = int(new_value) if cfg["type"] == "number" else new_value
                save_and_push(self._data)
                self._refresh_all()
                self._set_status(f"✔  Config '{cfg_key}' updated → {new_value}")

        self.push_screen(
            EditConfigModal(cfg_key, cfg["value"]),
            handle_result
        )

    def action_reload(self) -> None:
        self._data = load_flags()
        self._refresh_all()
        self._set_status("🔄  Reloaded from disk")


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    # Start HTTP server in background thread
    import server as srv
    t = threading.Thread(target=srv.run_server, daemon=True)
    t.start()

    # Launch Textual dashboard
    FlagManagerApp().run()
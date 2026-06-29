# Feature Flag Engine

A lightweight, self-hosted **Feature Flag & Remote Configuration Engine** built with **FastAPI**, **Textual**, and **Flutter**.

This project enables developers to remotely enable or disable application features, perform gradual feature rollouts, target specific user groups, update runtime configuration values, and instantly propagate changes to connected applications—without redeploying the client.

---

## Features

* FastAPI backend with REST APIs
* Interactive Textual terminal dashboard
* Real-time updates using WebSockets
* Automatic HTTP polling fallback
* Percentage-based feature rollouts
* User group targeting (`everyone`, `beta`, `staff`, ...)
* Remote configuration management
* Built-in audit logging
* Flutter Feature Flag SDK
* User simulation console for rollout testing
* JSON-based persistence

---

# Architecture

```text
                    Textual Dashboard
                           │
         ┌─────────────────┴─────────────────┐
         │                                   │
PATCH /flag/{name}                   PATCH /config/{key}
         │                                   │
         └──────────────┬────────────────────┘
                        │
                 FastAPI Backend
                 (Port 8080)
        ┌───────────────┴────────────────┐
        │                                │
   config.json                    WebSocket Server
        │                                │
        └───────────────┬────────────────┘
                        │
                Flutter Feature SDK
        ├── WebSocket Listener
        ├── HTTP Polling Fallback
        ├── Rollout Evaluation
        ├── User Group Targeting
        └── Local Cache
                        │
                 Flutter Demo App
```

---

# Technology Stack

| Component     | Technology         |
| ------------- | ------------------ |
| Backend       | FastAPI            |
| Dashboard     | Textual            |
| Client SDK    | Flutter / Dart     |
| Communication | REST + WebSockets  |
| Storage       | JSON               |
| Language      | Python 3.11+, Dart |

---

# Project Structure

```text
feature-flag-engine
│
├── server
│   ├── app.py              # FastAPI backend
│   ├── dashboard.py        # Textual dashboard
│   ├── config.json         # Feature flags & configs
│   └── audit.json          # Audit log
│
├── flutter_client
│   ├── lib
│   │   ├── feature_flag.dart
│   │   ├── home_screen.dart
│   │   └── main.dart
│   └── pubspec.yaml
│
├── requirements.txt
└── README.md
```

---

# Configuration Schema

```json
{
  "flags": {
    "dark_mode_beta": {
      "enabled": true,
      "rollout": 100,
      "groups": ["everyone"]
    },
    "new_checkout_flow": {
      "enabled": true,
      "rollout": 20,
      "groups": ["beta"]
    },
    "ai_recommendations": {
      "enabled": true,
      "rollout": 10,
      "groups": ["everyone"]
    }
  },

  "configs": {
    "welcome_message": "Hello, World!",
    "max_login_attempts": 5
  }
}
```

---

# Backend API

## REST Endpoints

| Method  | Endpoint        | Description                                                                 |
| ------- | --------------- | --------------------------------------------------------------------------- |
| `GET`   | `/config`       | Return the complete feature flag and configuration snapshot                 |
| `PATCH` | `/flag/{name}`  | Update a feature flag's enabled state, rollout percentage, or target groups |
| `PATCH` | `/config/{key}` | Update a remote configuration value                                         |
| `POST`  | `/reload`       | Reload configuration from disk and broadcast changes                        |
| `GET`   | `/audit`        | Return the latest audit log entries                                         |

---

## WebSocket

```
ws://localhost:8080/ws
```

Clients receive a configuration snapshot immediately after connecting and every time the configuration changes.

Example payload

```json
{
    "type": "config_update",
    "data": { ... }
}
```

---

# Flutter SDK

Initialize once during startup.

```dart
await FeatureFlag.initialize(
  "http://localhost:8080",
  userId: "alice",
  group: "beta",
  isBeta: true,
);
```

Evaluate feature flags.

```dart
if (FeatureFlag.isEnabled("dark_mode_beta")) {
    // Show new UI
}
```

Retrieve remote configuration values.

```dart
String? message = FeatureFlag.getString("welcome_message");

num? attempts = FeatureFlag.getNumber("max_login_attempts");
```

Switch users dynamically.

```dart
FeatureFlag.setUser(
    UserContext(
        userId: "bob",
        group: "everyone",
    ),
);
```

Listen for live updates.

```dart
StreamBuilder(
  stream: FeatureFlag.stream,
  builder: (context, _) {
    ...
  },
);
```

---

# Feature Evaluation

A feature is enabled only if **all** of the following conditions are satisfied:

* The feature flag is enabled.
* The user belongs to one of the permitted groups.
* The rollout bucket falls within the configured rollout percentage.

Supported groups include:

* `everyone`
* `beta`
* `staff`
* Any custom user-defined group

Rollout is deterministic using stable hashing.

```text
bucket = stableHash(flagId + "_" + userId) % 100

enabled = bucket < rollout
```

This ensures the same user consistently receives the same feature assignment.

---

# Keyboard Shortcuts

| Key             | Action                                                                        |
| --------------- | ----------------------------------------------------------------------------- |
| **Space**       | Toggle the selected feature flag ON/OFF                                       |
| **Enter**       | Edit the selected feature flag (rollout/groups) or remote configuration value |
| **Tab**         | Switch focus between Feature Flags and Remote Configs                         |
| **Shift + Tab** | Move focus to the previous table                                              |
| **R**           | Reload configuration from disk and broadcast updates                          |
| **Q**           | Quit the dashboard                                                            |

---

# Running the Project

## 1. Clone the repository

```bash
git clone <repository-url>
cd feature-flag-engine
```

---

## 2. Install Python dependencies

```bash
pip install -r requirements.txt
```

---

## 3. Launch the dashboard

```bash
python3 server/dashboard.py
```

This starts:

* FastAPI Backend (Port **8080**)
* Textual Dashboard

---

## 4. Launch the Flutter demo

```bash
cd flutter_client

flutter pub get

flutter run -d chrome
```

or

```bash
flutter run -d macos
```

---

# Demo Workflow

1. Start the FastAPI backend and Textual dashboard.
2. Launch the Flutter application.
3. Toggle feature flags from the dashboard.
4. Observe the Flutter UI updating instantly via WebSockets.
5. Switch simulated users to verify rollout percentages and group targeting.
6. Inspect the live audit log after every configuration change.

---

# Verified Endpoints

| Endpoint              | Status |
| --------------------- | ------ |
| `GET /config`         | ✅      |
| `PATCH /flag/{name}`  | ✅      |
| `PATCH /config/{key}` | ✅      |
| `POST /reload`        | ✅      |
| `GET /audit`          | ✅      |
| `WebSocket /ws`       | ✅      |

---

# Future Improvements

* SQLite/PostgreSQL persistence
* Authentication & role-based access
* Scheduled feature releases
* Feature dependencies
* Multi-environment support (Development / Testing / Production)
* Configuration import/export
* Dashboard analytics
* A/B experimentation support

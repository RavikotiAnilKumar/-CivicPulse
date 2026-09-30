# CivicPulse AI

CivicPulse is a hackathon prototype for turning multilingual community reports
into structured issues and explainable infrastructure priorities. It includes
a Flutter citizen-report UI, a government dashboard, a FastAPI backend, and
illustrative CSV datasets.

## Prototype scope

- Submit a citizen report as text or speech and receive structured analysis
  from the API.
- Demonstrate Telugu language detection and one sample translation without an
  external AI key.
- View priority score inputs, their weights, and a plain-language explanation.
- Voice input uses the device/browser speech recognition service and requests
  microphone permission.
- Reports are stored in a local SQLite database. A WebSocket pushes report
  submissions to the dashboard, which reloads its aggregates and recent-report
  feed immediately.
- Explore seeded dashboard totals, hotspot markers, priority areas, and project
  recommendations; submitted reports are incorporated into those views.
- Live WhatsApp/messaging integrations, user accounts, and a production
  database/service are not included.

All sample metrics, affected-population estimates, and costs are illustrative.
The prototype score is not an official government allocation formula.
The dashboard combines these seeded starting metrics with saved submissions;
the dashboard WebSocket sends new report events immediately.

## Structure

```text
CivicPulse_AI/
├── frontend/
│   ├── lib/main.dart
│   ├── pubspec.yaml
│   └── analysis_options.yaml
├── backend/
│   ├── main.py
│   ├── requirements.txt
│   ├── test_main.py
│   └── data/
│       ├── citizen_requests.csv
│       ├── infrastructure.csv
│       └── demographics.csv
├── docs/
│   ├── priority_algorithm.md
│   └── demo_script.md
└── README.md
```

## Run the backend

From the project root in PowerShell:

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Open the interactive API docs at <http://127.0.0.1:8000/docs>. Check
`GET /api/health`, submit reports to `POST /api/report`, and load the dashboard
with `GET /api/dashboard`.

Run backend tests from the `backend` directory:

```powershell
python -m pytest
```

## Run Flutter

Install Flutter and an Android SDK, then:

```powershell
cd frontend
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Web support is included so the browser demo can use its speech recognition
implementation. On Chrome, allow microphone access when prompted. Speech
recognition availability and supported languages depend on the browser and
operating system.

The default API URL, `http://10.0.2.2:8000`, is for the Android emulator. For a
physical Android device on the same network, pass the development machine's LAN
address:

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000
```

For Flutter web or desktop, use the host loopback address:

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

The backend permits cross-origin requests for this local prototype. The local
database lives at `backend/data/civicpulse.db`; set `CIVICPULSE_DB_PATH` to
change its location. Do not delete that file if you want to retain local
submissions. Restrict CORS origins, use authenticated HTTPS/WSS, and review data
retention and access controls before deployment.

## Scoring

The backend applies the documented weights:

```text
30% Citizen Demand
25% Infrastructure Gap
20% Population Impact
15% Urgency
10% Investment Gap
```

See [docs/priority_algorithm.md](docs/priority_algorithm.md) for bands,
limitations, and safeguards. The initial rules are deterministic demo
heuristics—not an LLM—and should be replaced only after selecting and validating
appropriate models and data governance.

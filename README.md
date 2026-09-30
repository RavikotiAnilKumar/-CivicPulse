# CivicPulse AI

CivicPulse is a hackathon prototype for turning community reports into
structured issues and explainable infrastructure priorities across BRICS
countries. It includes a Flutter citizen-report UI, a country-filterable
government dashboard, a FastAPI backend, and joined illustrative CSV datasets.

## BRICS theme: Innovation

CivicPulse presents **citizen voice as public-sector innovation**: it combines
multilingual reporting, explainable prioritization, regional data fusion, and
cross-country learning in one civic-tech demonstration. Its innovation claim
is the prototype workflow and transparent decision support—not autonomous AI
or verified impact. The regional examples are synthetic, and project priorities
are suggestions for human review rather than government decisions.

## Prototype scope

- Submit a citizen report as text or speech, choosing a BRICS country and a
  configured region.
- Demonstrate script/keyword-based language detection and classification for
  selected local languages. One exact Telugu sample has a demo translation;
  general-purpose translation is not implemented.
- View priority score inputs, their weights, and a plain-language explanation.
- Voice input uses the device/browser speech recognition service and requests
  microphone permission.
- Reports are stored in a local SQLite database. A WebSocket pushes report
  submissions to the dashboard, which reloads its aggregates and recent-report
  feed immediately.
- Filter the live dashboard by country or across all five BRICS countries.
- Explore regional hotspots and recommendations joined from citizen request,
  demographic, infrastructure-index, and illustrative investment-plan data.
  Newly submitted reports are persisted and incorporated into the dashboard
  over WebSockets.
- Live WhatsApp/messaging integrations, user accounts, and a production
  database/service are not included.

**All regional, demographic, infrastructure, request-volume, and investment
plan values are synthetic demonstration data.** They are not verified national
statistics, public budget records, or government recommendations. The prototype
score is not an official allocation formula. Language processing is a
deterministic demonstration, not an LLM or production translation service.

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
│       ├── demographics.csv
│       └── investment_plans.csv
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
`GET /api/health`, retrieve report country/region options from
`GET /api/countries`, submit reports to `POST /api/report`, and load all-country
or country-filtered analytics with `GET /api/dashboard?country=India`.

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
normalization, limitations, and safeguards. The rules are deterministic demo
heuristics—not an LLM—and should be replaced only after selecting and validating
appropriate models and data governance.

## Challenge scope and production gaps

This implementation provides a cross-country **demo slice**, not a production
Digital Public Good platform. It has selectable demo regions in Brazil, China,
India, Russia, and South Africa. It does not connect to authoritative BRICS
demographic or investment datasets, messaging providers, or external translation
and AI services. Production work must add licensed/official data connectors,
country-specific administrative boundaries, consent and retention controls,
secure identity/access, human review, accessibility/localization, and
independently validated language models and scoring.

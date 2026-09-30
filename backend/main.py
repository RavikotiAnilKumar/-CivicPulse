from __future__ import annotations

import asyncio
import csv
import json
import os
import re
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterator, Literal

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field


BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"

app = FastAPI(
    title="CivicPulse AI API",
    description=(
        "Hackathon prototype API. Language detection and issue classification "
        "are deterministic demo heuristics, not an official allocation model."
    ),
    version="0.1.0",
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)


class ReportInput(BaseModel):
    text: str = Field(min_length=4, max_length=2000)
    location: str = Field(default="Guntur", min_length=2, max_length=100)
    language: str = Field(default="Auto-detect", max_length=40)


class ScoreBreakdown(BaseModel):
    citizen_demand: float
    infrastructure_gap: float
    population_impact: float
    urgency: float
    investment_gap: float


class AnalysisResult(BaseModel):
    report_id: int | None = None
    submitted_at: str | None = None
    language: str
    translation: str
    category: str
    issue: str
    location: str
    severity: Literal["Low", "Medium", "High", "Critical"]
    people_affected: int
    summary: str
    priority_score: float
    priority: Literal["Low", "Medium", "High", "Critical"]
    score_breakdown: ScoreBreakdown
    score_explanation: str
    recommendation: str


class PriorityArea(BaseModel):
    category: str
    requests: int
    priority: Literal["Low", "Medium", "High", "Critical"]


class Recommendation(BaseModel):
    project: str
    location: str
    population: int
    requests: int
    infrastructure_index: int
    estimate: str
    priority: Literal["Low", "Medium", "High", "Critical"]
    priority_score: float


class DashboardResponse(BaseModel):
    metrics: dict[str, int]
    priority_areas: list[PriorityArea]
    recommendations: list[Recommendation]
    hotspots: list[dict[str, str | float]]
    recent_reports: list[AnalysisResult]
    prototype_notice: str


class DashboardConnections:
    def __init__(self) -> None:
        self.clients: set[WebSocket] = set()
        self.lock = asyncio.Lock()

    async def connect(self, websocket: WebSocket) -> None:
        await websocket.accept()
        async with self.lock:
            self.clients.add(websocket)

    async def disconnect(self, websocket: WebSocket) -> None:
        async with self.lock:
            self.clients.discard(websocket)

    async def publish(self, event: dict[str, object]) -> None:
        async with self.lock:
            clients = tuple(self.clients)
        stale: list[WebSocket] = []
        for client in clients:
            try:
                await client.send_json(event)
            except (OSError, RuntimeError, WebSocketDisconnect):
                stale.append(client)
        if stale:
            async with self.lock:
                self.clients.difference_update(stale)


WEIGHTS = {
    "citizen_demand": 0.30,
    "infrastructure_gap": 0.25,
    "population_impact": 0.20,
    "urgency": 0.15,
    "investment_gap": 0.10,
}

LANGUAGE_NAMES = {
    "Telugu": "Telugu",
    "Hindi": "Hindi",
    "Tamil": "Tamil",
    "Kannada": "Kannada",
    "Bengali": "Bengali",
    "English": "English",
}

TELUGU_WATER = "మా గ్రామంలో తాగునీటి సమస్య ఉంది."
TELUGU_ROAD = "మా గ్రామంలో రోడ్డు చాలా పాడైపోయింది."
dashboard_connections = DashboardConnections()
SAMPLE_METRICS = {
    "citizen_requests": 12486,
    "critical_issues": 1248,
    "infrastructure_gaps": 386,
    "districts_covered": 28,
}
SAMPLE_AREAS = [
    PriorityArea(category="Roads", requests=342, priority="High"),
    PriorityArea(category="Water", requests=287, priority="Critical"),
    PriorityArea(category="Healthcare", requests=211, priority="High"),
    PriorityArea(category="Education", requests=164, priority="Medium"),
    PriorityArea(category="Street Lighting", requests=109, priority="Medium"),
]


def _database_path() -> Path:
    return Path(os.environ.get("CIVICPULSE_DB_PATH", str(DATA_DIR / "civicpulse.db")))


@contextmanager
def _connect_database() -> Iterator[sqlite3.Connection]:
    path = _database_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(path, timeout=10)
    connection.row_factory = sqlite3.Row
    try:
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS reports (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                submitted_at TEXT NOT NULL,
                result_json TEXT NOT NULL
            )
            """
        )
        yield connection
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


def _saved_reports(limit: int = 5000) -> list[AnalysisResult]:
    with _connect_database() as connection:
        rows = connection.execute(
            "SELECT result_json FROM reports ORDER BY id DESC LIMIT ?", (limit,)
        ).fetchall()
    return [AnalysisResult.model_validate_json(row["result_json"]) for row in rows]


def _read_csv(filename: str) -> list[dict[str, str]]:
    path = DATA_DIR / filename
    try:
        with path.open(encoding="utf-8", newline="") as file:
            return list(csv.DictReader(file))
    except OSError as exc:
        raise HTTPException(
            status_code=500, detail=f"Unable to read prototype data file: {filename}"
        ) from exc


def detect_language(text: str) -> str:
    for name, pattern in (
        ("Telugu", r"[\u0C00-\u0C7F]"),
        ("Hindi", r"[\u0900-\u097F]"),
        ("Tamil", r"[\u0B80-\u0BFF]"),
        ("Kannada", r"[\u0C80-\u0CFF]"),
        ("Bengali", r"[\u0980-\u09FF]"),
    ):
        if re.search(pattern, text):
            return name
    return "English"


def _classify(text: str) -> tuple[str, str]:
    normalized = text.lower()
    if re.search(r"water|தண்ணீர்|ನೀರು|నీరు|నీటి|తాగునీటి|पानी|जल", normalized):
        return "Water", "Water access"
    if re.search(r"road|రోడ్డు|రహదారి|सड़क|சாலை|ರಸ್ತೆ", normalized):
        return "Roads", "Damaged road"
    if re.search(r"light|lighting|వెలుగు|లైటు|रोशनी|விளக்கு", normalized):
        return "Street Lighting", "Missing street lights"
    if re.search(r"health|hospital|ఆరోగ్|स्वास्थ्य|மருத்துவ", normalized):
        return "Healthcare", "Healthcare access"
    if re.search(r"school|education|విద్య|शिक्षा|கல்வி", normalized):
        return "Education", "Education access"
    return "Infrastructure", "Community infrastructure issue"


def _translation(text: str, language: str, category: str) -> str:
    examples = {
        TELUGU_WATER: "There is a drinking water problem in our village.",
        TELUGU_ROAD: "The road in our village is badly damaged.",
    }
    if text.strip() in examples:
        return examples[text.strip()]
    if language == "English":
        return text
    return (
        f"Demo translation unavailable for this sentence "
        f"(detected {language}; classified as {category.lower()})."
    )


def calculate_priority(scores: ScoreBreakdown) -> tuple[float, str]:
    score = round(
        scores.citizen_demand * WEIGHTS["citizen_demand"]
        + scores.infrastructure_gap * WEIGHTS["infrastructure_gap"]
        + scores.population_impact * WEIGHTS["population_impact"]
        + scores.urgency * WEIGHTS["urgency"]
        + scores.investment_gap * WEIGHTS["investment_gap"],
        1,
    )
    if score >= 85:
        priority = "Critical"
    elif score >= 70:
        priority = "High"
    elif score >= 40:
        priority = "Medium"
    else:
        priority = "Low"
    return score, priority


def analyze_report(report: ReportInput) -> AnalysisResult:
    language = (
        detect_language(report.text)
        if report.language == "Auto-detect"
        else report.language
    )
    category, issue = _classify(report.text)
    infrastructure = next(
        (
            row
            for row in _read_csv("infrastructure.csv")
            if row["district"].casefold() == report.location.casefold()
        ),
        None,
    )
    if infrastructure is None:
        infrastructure = _read_csv("infrastructure.csv")[0]

    index_key = {
        "Roads": "road_index",
        "Water": "water_index",
        "Street Lighting": "road_index",
        "Healthcare": "health_index",
        "Education": "education_index",
        "Infrastructure": "road_index",
    }[category]
    infrastructure_index = int(infrastructure[index_key])
    infrastructure_gap = 100 - infrastructure_index

    is_urgent = bool(
        re.search(
            r"urgent|danger|unsafe|critical|no water|no light|damaged|damage|పాడై|సమస్య",
            report.text,
            re.I,
        )
    )
    severity = "High" if is_urgent else "Medium"
    if infrastructure_gap >= 75 and is_urgent:
        severity = "Critical"

    people_affected = 12600 if category == "Water" else 850
    scores = ScoreBreakdown(
        citizen_demand=82,
        infrastructure_gap=float(infrastructure_gap),
        population_impact=min(100.0, round(people_affected / 150, 1)),
        urgency=90.0 if is_urgent else 58.0,
        investment_gap=81.0,
    )
    priority_score, priority = calculate_priority(scores)
    recommendation = (
        "Prioritize drinking-water infrastructure improvements."
        if category == "Water"
        else "Assess and rehabilitate the affected community infrastructure."
        if category != "Roads"
        else "Prioritize road rehabilitation and a safety review near the school zone."
    )
    summary = (
        f"{issue} reported in {report.location}. The request is marked {severity.lower()} "
        f"priority and an estimated {people_affected:,} people may be affected."
    )
    explanation = (
        f"Demand contributes {scores.citizen_demand * WEIGHTS['citizen_demand']:.1f} points, "
        f"infrastructure gap {scores.infrastructure_gap * WEIGHTS['infrastructure_gap']:.1f}, "
        f"population impact {scores.population_impact * WEIGHTS['population_impact']:.1f}, "
        f"urgency {scores.urgency * WEIGHTS['urgency']:.1f}, and investment gap "
        f"{scores.investment_gap * WEIGHTS['investment_gap']:.1f}."
    )
    return AnalysisResult(
        language=language,
        translation=_translation(report.text, language, category),
        category=category,
        issue=issue,
        location=report.location,
        severity=severity,
        people_affected=people_affected,
        summary=summary,
        priority_score=priority_score,
        priority=priority,
        score_breakdown=scores,
        score_explanation=explanation,
        recommendation=recommendation,
    )


@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok", "mode": "prototype"}


@app.post("/api/report", response_model=AnalysisResult)
async def submit_report(report: ReportInput) -> AnalysisResult:
    analyzed = analyze_report(report)
    submitted_at = datetime.now(timezone.utc).isoformat()
    with _connect_database() as connection:
        cursor = connection.execute(
            "INSERT INTO reports (submitted_at, result_json) VALUES (?, ?)",
            (submitted_at, analyzed.model_dump_json()),
        )
        report_id = cursor.lastrowid
        saved = analyzed.model_copy(
            update={"report_id": report_id, "submitted_at": submitted_at}
        )
        connection.execute(
            "UPDATE reports SET result_json = ? WHERE id = ?",
            (saved.model_dump_json(), report_id),
        )
    await dashboard_connections.publish(
        {"type": "report_created", "report": saved.model_dump(mode="json")}
    )
    return saved


@app.get("/api/dashboard", response_model=DashboardResponse)
def dashboard() -> DashboardResponse:
    reports = _saved_reports()
    category_counts: dict[str, int] = {}
    category_priorities: dict[str, list[str]] = {}
    for report in reports:
        category_counts[report.category] = category_counts.get(report.category, 0) + 1
        category_priorities.setdefault(report.category, []).append(report.priority)

    areas = [
        PriorityArea(
            category=area.category,
            requests=area.requests + category_counts.pop(area.category, 0),
            priority=max(
                [area.priority, *category_priorities.get(area.category, [])],
                key=lambda value: {
                    "Low": 0,
                    "Medium": 1,
                    "High": 2,
                    "Critical": 3,
                }[value],
            ),
        )
        for area in SAMPLE_AREAS
    ]
    areas.extend(
        PriorityArea(
            category=category,
            requests=count,
            priority=max(
                (report.priority for report in reports if report.category == category),
                key=lambda value: {
                    "Low": 0,
                    "Medium": 1,
                    "High": 2,
                    "Critical": 3,
                }[value],
            ),
        )
        for category, count in category_counts.items()
    )

    dynamic_recommendations = [
        Recommendation(
            project=f"{report.category} improvement: {report.issue}",
            location=f"{report.location} District",
            population=report.people_affected,
            requests=sum(
                saved.category == report.category for saved in reports
            ),
            infrastructure_index=max(
                0, 100 - int(report.score_breakdown.infrastructure_gap)
            ),
            estimate="Needs assessment",
            priority=report.priority,
            priority_score=report.priority_score,
        )
        for report in reports[:5]
    ]
    dynamic_hotspots = [
        {
            "district": report.location,
            "latitude": 16.3067,
            "longitude": 80.4365,
            "priority": report.priority,
        }
        for report in reports[:10]
    ]
    return DashboardResponse(
        metrics={
            "citizen_requests": SAMPLE_METRICS["citizen_requests"] + len(reports),
            "critical_issues": SAMPLE_METRICS["critical_issues"]
            + sum(report.priority == "Critical" for report in reports),
            "infrastructure_gaps": SAMPLE_METRICS["infrastructure_gaps"]
            + sum(report.severity in ("High", "Critical") for report in reports),
            "districts_covered": SAMPLE_METRICS["districts_covered"]
            + len(
                {
                    report.location.casefold()
                    for report in reports
                    if report.location.casefold()
                    not in {
                        row["district"].casefold()
                        for row in _read_csv("citizen_requests.csv")
                    }
                }
            ),
        },
        priority_areas=areas,
        recommendations=dynamic_recommendations
        + [
            Recommendation(
                project="Road rehabilitation near School Zone",
                location="Guntur District",
                population=850,
                requests=147,
                infrastructure_index=32,
                estimate="₹18 lakh",
                priority="High",
                priority_score=87.0,
            ),
            Recommendation(
                project="Rural drinking-water access upgrade",
                location="Krishna District",
                population=12600,
                requests=287,
                infrastructure_index=28,
                estimate="₹2.4 crore",
                priority="Critical",
                priority_score=89.0,
            ),
        ],
        hotspots=dynamic_hotspots
        + [
            {"district": "Guntur", "latitude": 16.3067, "longitude": 80.4365, "priority": "High"},
            {"district": "Krishna", "latitude": 16.6100, "longitude": 80.7214, "priority": "Critical"},
            {"district": "Vizag", "latitude": 17.6868, "longitude": 83.2185, "priority": "Medium"},
            {"district": "Nellore", "latitude": 14.4426, "longitude": 79.9865, "priority": "Low"},
        ],
        prototype_notice=(
            "All dashboard totals and project estimates are illustrative sample data. "
            "Priority scores are a prototype model, not an official government allocation formula."
        ),
        recent_reports=reports[:20],
    )


@app.websocket("/ws/dashboard")
async def dashboard_updates(websocket: WebSocket) -> None:
    await dashboard_connections.connect(websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        await dashboard_connections.disconnect(websocket)

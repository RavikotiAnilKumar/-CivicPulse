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
    country: str = Field(default="India", min_length=2, max_length=80)
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
    country: str = "India"
    country_code: str = "IN"
    language: str
    translation: str
    category: str
    issue: str
    location: str
    infrastructure_index: int = 0
    severity: Literal["Low", "Medium", "High", "Critical"]
    people_affected: int
    summary: str
    priority_score: float
    priority: Literal["Low", "Medium", "High", "Critical"]
    score_breakdown: ScoreBreakdown
    score_explanation: str
    recommendation: str
    investment_plan: str = "No matching sample plan"
    latitude: float = 0
    longitude: float = 0


class CountryOption(BaseModel):
    name: str
    code: str
    languages: list[str]
    regions: list[str]


class PriorityArea(BaseModel):
    category: str
    requests: int
    priority: Literal["Low", "Medium", "High", "Critical"]


class Recommendation(BaseModel):
    project: str
    location: str
    country: str = "India"
    category: str = "Infrastructure"
    population: int
    requests: int
    infrastructure_index: int
    estimate: str
    priority: Literal["Low", "Medium", "High", "Critical"]
    priority_score: float
    score_breakdown: ScoreBreakdown
    explanation: str


class DashboardResponse(BaseModel):
    selected_country: str
    countries: list[CountryOption]
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

TELUGU_WATER = "మా గ్రామంలో తాగునీటి సమస్య ఉంది."
TELUGU_ROAD = "మా గ్రామంలో రోడ్డు చాలా పాడైపోయింది."
dashboard_connections = DashboardConnections()
COUNTRY_LANGUAGES = {
    "Brazil": ["Portuguese", "English"],
    "China": ["Chinese (Mandarin)", "English"],
    "India": ["English", "Hindi", "Telugu", "Tamil", "Kannada", "Bengali"],
    "Russia": ["Russian", "English"],
    "South Africa": ["English", "isiZulu", "isiXhosa", "Afrikaans"],
}


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


def _country_options() -> list[CountryOption]:
    demographics = _read_csv("demographics.csv")
    codes = {
        row["country"]: row["country_code"]
        for row in _read_csv("infrastructure.csv")
    }
    regions_by_country: dict[str, list[str]] = {}
    for row in demographics:
        regions_by_country.setdefault(row["country"], []).append(row["region"])
    return [
        CountryOption(
            name=country,
            code=codes[country],
            languages=languages,
            regions=regions_by_country[country],
        )
        for country, languages in COUNTRY_LANGUAGES.items()
        if country in regions_by_country
    ]


def _matching_row(
    filename: str, country: str, region: str, category: str | None = None
) -> dict[str, str] | None:
    return next(
        (
            row
            for row in _read_csv(filename)
            if row["country"].casefold() == country.casefold()
            and row["region"].casefold() == region.casefold()
            and (category is None or row.get("category", "").casefold() == category.casefold())
        ),
        None,
    )


def detect_language(text: str) -> str:
    for name, pattern in (
        ("Telugu", r"[\u0C00-\u0C7F]"),
        ("Hindi", r"[\u0900-\u097F]"),
        ("Tamil", r"[\u0B80-\u0BFF]"),
        ("Kannada", r"[\u0C80-\u0CFF]"),
        ("Bengali", r"[\u0980-\u09FF]"),
        ("Russian", r"[\u0400-\u04FF]"),
        ("Chinese (Mandarin)", r"[\u4E00-\u9FFF]"),
    ):
        if re.search(pattern, text):
            return name
    if re.search(r"\b(água|bairro|estrada|saúde|iluminação)\b", text, re.I):
        return "Portuguese"
    return "English"


def _classify(text: str) -> tuple[str, str]:
    normalized = text.lower()
    if re.search(
        r"water|água|вод|水|தண்ணீர்|ನೀರು|నీరు|నీటి|తాగునీటి|पानी|जल",
        normalized,
    ):
        return "Water", "Water access"
    if re.search(r"road|estrada|дорог|道路|రోడ్డు|రహదారి|सड़क|சாலை|ರಸ್ತೆ", normalized):
        return "Roads", "Damaged road"
    if re.search(
        r"light|lighting|iluminação|свет|照明|వెలుగు|లైటు|रोशनी|விளக்கு",
        normalized,
    ):
        return "Street Lighting", "Missing street lights"
    if re.search(
        r"health|hospital|saúde|больниц|医院|ఆరోగ్|स्वास्थ्य|மருத்துவ",
        normalized,
    ):
        return "Healthcare", "Healthcare access"
    if re.search(r"school|education|школ|学校|విద్య|शिक्षा|கல்வி", normalized):
        return "Education", "Education access"
    if re.search(r"transit|bus|transport|транспорт|公共交通", normalized):
        return "Public Transit", "Public transit access"
    if re.search(r"electricity|power|энерг|电力", normalized):
        return "Electricity", "Electricity access"
    if re.search(r"heating|тепл|供暖", normalized):
        return "Heating", "Heating access"
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


def _category_index(row: dict[str, str], category: str) -> int:
    index_key = {
        "Roads": "road_index",
        "Water": "water_index",
        "Street Lighting": "road_index",
        "Healthcare": "health_index",
        "Education": "education_index",
        "Public Transit": "transit_index",
        "Electricity": "energy_index",
        "Heating": "energy_index",
        "Infrastructure": "road_index",
    }.get(category, "road_index")
    return int(row[index_key])


def _severity_score(severity: str) -> float:
    return {"Low": 25.0, "Medium": 50.0, "High": 75.0, "Critical": 100.0}[
        severity
    ]


def _score_explanation(scores: ScoreBreakdown) -> str:
    return (
        f"Demand contributes {scores.citizen_demand * WEIGHTS['citizen_demand']:.1f} points, "
        f"infrastructure gap {scores.infrastructure_gap * WEIGHTS['infrastructure_gap']:.1f}, "
        f"population impact {scores.population_impact * WEIGHTS['population_impact']:.1f}, "
        f"urgency {scores.urgency * WEIGHTS['urgency']:.1f}, and investment gap "
        f"{scores.investment_gap * WEIGHTS['investment_gap']:.1f}."
    )


def _investment_label(plan: dict[str, str] | None) -> str:
    if plan is None:
        return "No matching sample plan"
    amount = float(plan["planned_amount_millions"])
    committed_amount = float(plan["committed_amount_millions"])
    currency = plan["currency"]
    if currency == "INR":
        value = f"₹{amount / 10:.1f} crore"
        committed_value = f"₹{committed_amount / 10:.1f} crore"
    else:
        value = f"{currency} {amount:g} million"
        committed_value = f"{currency} {committed_amount:g} million"
    return (
        f"{plan['project_name']}: {value} planned, "
        f"{committed_value} committed "
        f"({plan['fiscal_year']}; illustrative)"
    )


def _score_inputs(
    country: str,
    region: str,
    category: str,
    requests: int,
    population_affected: int,
    severity: str,
) -> tuple[ScoreBreakdown, int, dict[str, str] | None]:
    infrastructure = _matching_row("infrastructure.csv", country, region)
    demographics = _matching_row("demographics.csv", country, region)
    if infrastructure is None or demographics is None:
        raise HTTPException(status_code=422, detail="Unknown country or region.")
    plan = _matching_row("investment_plans.csv", country, region, category)
    category_rows = [
        row
        for row in _read_csv("citizen_requests.csv")
        if row["country"].casefold() == country.casefold()
        and row["category"].casefold() == category.casefold()
    ]
    demand_max = max((int(row["requests"]) for row in category_rows), default=1)
    planned = float(plan["planned_amount_millions"]) if plan else 0
    committed = float(plan["committed_amount_millions"]) if plan else 0
    population = int(demographics["population"])
    vulnerable_population = int(demographics["vulnerable_population"])
    population_impact_threshold = max(
        1, min(int(vulnerable_population * 0.10), int(population * 0.03))
    )
    scores = ScoreBreakdown(
        citizen_demand=min(100.0, round(100 * requests / max(demand_max, 1), 1)),
        infrastructure_gap=float(100 - _category_index(infrastructure, category)),
        population_impact=min(
            100.0,
            round(100 * population_affected / population_impact_threshold, 1),
        ),
        urgency=_severity_score(severity),
        investment_gap=(
            round(100 * max(0, planned - committed) / planned, 1)
            if planned
            else 50.0
        ),
    )
    return scores, _category_index(infrastructure, category), plan


def analyze_report(report: ReportInput) -> AnalysisResult:
    language = (
        detect_language(report.text)
        if report.language == "Auto-detect"
        else report.language
    )
    options = {option.name.casefold(): option for option in _country_options()}
    country_option = options.get(report.country.casefold())
    if country_option is None:
        raise HTTPException(status_code=422, detail="Select a supported BRICS country.")
    if (
        report.language != "Auto-detect"
        and report.language not in country_option.languages
    ):
        raise HTTPException(
            status_code=422,
            detail=f"{report.language} is not configured for {country_option.name}.",
        )
    if not any(
        region.casefold() == report.location.casefold()
        for region in country_option.regions
    ):
        raise HTTPException(
            status_code=422,
            detail=f"{report.location} is not a configured region in {country_option.name}.",
        )
    regional_data = _matching_row(
        "infrastructure.csv", country_option.name, report.location
    )
    demographics = _matching_row(
        "demographics.csv", country_option.name, report.location
    )
    if regional_data is None or demographics is None:
        raise HTTPException(
            status_code=422,
            detail="Regional infrastructure or demographic data is unavailable.",
        )
    category, issue = _classify(report.text)
    baseline = _matching_row(
        "citizen_requests.csv", country_option.name, report.location, category
    )
    saved = [
        item
        for item in _saved_reports()
        if item.country.casefold() == country_option.name.casefold()
        and item.location.casefold() == report.location.casefold()
        and item.category.casefold() == category.casefold()
    ]
    severity = "High" if re.search(
        r"urgent|danger|unsafe|critical|no water|no light|damaged|damage|பாடை|సమస్య",
        report.text,
        re.I,
    ) else "Medium"
    if baseline and baseline["severity"] == "Critical" and severity == "High":
        severity = "Critical"
    people_affected = int(baseline["population_affected"]) if baseline else max(
        1, int(int(demographics["vulnerable_population"]) * 0.01)
    )
    requests = (int(baseline["requests"]) if baseline else 0) + len(saved) + 1
    scores, infrastructure_index, plan = _score_inputs(
        country_option.name,
        report.location,
        category,
        requests,
        people_affected,
        severity,
    )
    priority_score, priority = calculate_priority(scores)
    recommendation = (
        f"Prioritize {category.lower()} investment in {report.location}, "
        f"{country_option.name}; review the local plan and validate the unmet need."
        if category == "Water"
        else f"Assess and address the {issue.lower()} in {report.location}, "
        f"{country_option.name}; confirm scope with local authorities."
    )
    summary = (
        f"{issue} reported in {report.location}, {country_option.name}. "
        f"The request is marked {severity.lower()} "
        f"priority and an estimated {people_affected:,} people may be affected."
    )
    return AnalysisResult(
        language=language,
        translation=_translation(report.text, language, category),
        country=country_option.name,
        country_code=country_option.code,
        category=category,
        issue=issue,
        location=report.location,
        infrastructure_index=infrastructure_index,
        severity=severity,
        people_affected=people_affected,
        summary=summary,
        priority_score=priority_score,
        priority=priority,
        score_breakdown=scores,
        score_explanation=_score_explanation(scores),
        recommendation=recommendation,
        investment_plan=_investment_label(plan),
        latitude=float(regional_data["latitude"]),
        longitude=float(regional_data["longitude"]),
    )


@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok", "mode": "prototype"}


@app.get("/api/countries", response_model=list[CountryOption])
def countries() -> list[CountryOption]:
    return _country_options()


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
def dashboard(country: str = "All BRICS") -> DashboardResponse:
    country_options = _country_options()
    country_by_name = {option.name.casefold(): option.name for option in country_options}
    selected_country = (
        "All BRICS"
        if country.casefold() == "all brics"
        else country_by_name.get(country.casefold())
    )
    if selected_country is None:
        raise HTTPException(status_code=422, detail="Select a supported BRICS country.")

    baseline_rows = _read_csv("citizen_requests.csv")
    regions = _read_csv("infrastructure.csv")
    if selected_country != "All BRICS":
        baseline_rows = [
            row for row in baseline_rows if row["country"] == selected_country
        ]
        regions = [row for row in regions if row["country"] == selected_country]
    saved_reports = [
        report
        for report in _saved_reports()
        if selected_country == "All BRICS"
        or report.country.casefold() == selected_country.casefold()
    ]

    grouped: dict[tuple[str, str, str], dict[str, object]] = {}
    for row in baseline_rows:
        key = (row["country"], row["region"], row["category"])
        grouped[key] = {
            "requests": int(row["requests"]),
            "population": int(row["population_affected"]),
            "severity": row["severity"],
            "project": None,
        }
    for report in saved_reports:
        key = (report.country, report.location, report.category)
        values = grouped.setdefault(
            key,
            {
                "requests": 0,
                "population": report.people_affected,
                "severity": report.severity,
                "project": None,
            },
        )
        values["requests"] = int(values["requests"]) + 1
        values["population"] = max(int(values["population"]), report.people_affected)
        if _severity_score(report.severity) > _severity_score(str(values["severity"])):
            values["severity"] = report.severity

    candidate_rows: list[Recommendation] = []
    priority_areas: dict[str, dict[str, object]] = {}
    for (region_country, region, category), values in grouped.items():
        scores, index, plan = _score_inputs(
            region_country,
            region,
            category,
            int(values["requests"]),
            int(values["population"]),
            str(values["severity"]),
        )
        score, priority = calculate_priority(scores)
        area = priority_areas.setdefault(
            category, {"requests": 0, "priority": "Low"}
        )
        area["requests"] = int(area["requests"]) + int(values["requests"])
        if _severity_score(priority) > _severity_score(str(area["priority"])):
            area["priority"] = priority
        candidate_rows.append(
            Recommendation(
                project=plan["project_name"] if plan else f"{category} improvement",
                location=f"{region}, {region_country}",
                country=region_country,
                category=category,
                population=int(values["population"]),
                requests=int(values["requests"]),
                infrastructure_index=index,
                estimate=_investment_label(plan),
                priority=priority,
                priority_score=score,
                score_breakdown=scores,
                explanation=_score_explanation(scores),
            )
        )

    hotspots: list[dict[str, str | float]] = []
    for region_row in regions:
        related = [
            item
            for item in candidate_rows
            if item.country == region_row["country"]
            and item.location.startswith(f"{region_row['region']},")
        ]
        worst = max(
            related,
            key=lambda item: _severity_score(item.priority),
            default=None,
        )
        hotspots.append(
            {
                "district": region_row["region"],
                "country": region_row["country"],
                "latitude": float(region_row["latitude"]),
                "longitude": float(region_row["longitude"]),
                "priority": worst.priority if worst else "Low",
            }
        )

    gap_dimensions = (
        "road_index",
        "water_index",
        "health_index",
        "education_index",
        "transit_index",
        "energy_index",
    )
    infrastructure_gaps = sum(
        int(region[index]) < 50 for region in regions for index in gap_dimensions
    )
    baseline_total = sum(int(row["requests"]) for row in baseline_rows)
    critical_total = sum(
        int(row["requests"])
        for row in baseline_rows
        if row["severity"] == "Critical"
    ) + sum(report.priority == "Critical" for report in saved_reports)
    return DashboardResponse(
        selected_country=selected_country,
        countries=country_options,
        metrics={
            "citizen_requests": baseline_total + len(saved_reports),
            "critical_issues": critical_total,
            "infrastructure_gaps": infrastructure_gaps,
            "districts_covered": len(regions),
        },
        priority_areas=[
            PriorityArea(
                category=category,
                requests=int(values["requests"]),
                priority=str(values["priority"]),
            )
            for category, values in sorted(
                priority_areas.items(),
                key=lambda item: int(item[1]["requests"]),
                reverse=True,
            )
        ],
        recommendations=sorted(
            candidate_rows,
            key=lambda item: item.priority_score,
            reverse=True,
        )[:5],
        hotspots=hotspots,
        prototype_notice=(
            "BRICS country and regional records are synthetic demonstration data, "
            "not verified national statistics or adopted public budgets. "
            "Scores are an explainable prototype signal, not an official allocation formula."
        ),
        recent_reports=saved_reports[:20],
    )


@app.websocket("/ws/dashboard")
async def dashboard_updates(websocket: WebSocket) -> None:
    await dashboard_connections.connect(websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        await dashboard_connections.disconnect(websocket)

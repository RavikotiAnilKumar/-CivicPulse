from fastapi.testclient import TestClient

from main import app
from main import ReportInput, analyze_report, calculate_priority, ScoreBreakdown


def test_priority_score_uses_documented_weights_and_tiers():
    score, priority = calculate_priority(
        ScoreBreakdown(
            citizen_demand=82,
            infrastructure_gap=72,
            population_impact=68,
            urgency=90,
            investment_gap=81,
        )
    )
    assert score == 77.8
    assert priority == "High"


def test_telugu_water_report_is_classified_and_explained():
    result = analyze_report(
        ReportInput(text="మా గ్రామంలో తాగునీటి సమస్య ఉంది.", location="Guntur")
    )
    assert result.language == "Telugu"
    assert result.category == "Water"
    assert result.translation == "There is a drinking water problem in our village."
    assert result.priority_score > 0
    assert "contributes" in result.score_explanation


def test_english_road_report_is_classified():
    result = analyze_report(
        ReportInput(
            text="Our road near the village school is damaged and there are no street lights.",
            location="Guntur",
        )
    )
    assert result.language == "English"
    assert result.category == "Roads"
    assert result.location == "Guntur"
    assert result.country == "India"
    assert result.investment_plan.startswith("Rural road rehabilitation plan")


def test_brazilian_portuguese_report_uses_brazilian_regional_data():
    result = analyze_report(
        ReportInput(
            text="Falta água potável no meu bairro.",
            country="Brazil",
            location="Bahia",
            language="Auto-detect",
        )
    )
    assert result.language == "Portuguese"
    assert result.category == "Water"
    assert result.country_code == "BR"
    assert result.people_affected == 18400
    assert "BRL 52 million planned" in result.investment_plan


def test_chinese_report_detects_language_and_classifies_water():
    result = analyze_report(
        ReportInput(
            text="我们村里没有饮用水。",
            country="China",
            location="Guangdong",
        )
    )
    assert result.language == "Chinese (Mandarin)"
    assert result.category == "Water"
    assert result.country_code == "CN"
    assert result.score_breakdown.infrastructure_gap == 33


def test_country_endpoint_and_dashboard_aggregate_country_scoped_data():
    with TestClient(app) as client:
        countries = client.get("/api/countries").json()
        assert {item["code"] for item in countries} == {"BR", "CN", "IN", "RU", "ZA"}
        india = client.get("/api/dashboard?country=India").json()
        all_brics = client.get("/api/dashboard").json()
    assert india["selected_country"] == "India"
    assert india["metrics"]["districts_covered"] == 2
    assert all_brics["selected_country"] == "All BRICS"
    assert all_brics["metrics"]["districts_covered"] == 10
    assert all_brics["metrics"]["citizen_requests"] > india["metrics"]["citizen_requests"]
    assert {item["country"] for item in all_brics["recommendations"]} <= {
        "Brazil",
        "China",
        "India",
        "Russia",
        "South Africa",
    }
    assert all_brics["recommendations"][0]["score_breakdown"]
    assert "Demand contributes" in all_brics["recommendations"][0]["explanation"]


def test_submission_persists_and_updates_dashboard_in_realtime(tmp_path, monkeypatch):
    monkeypatch.setenv("CIVICPULSE_DB_PATH", str(tmp_path / "reports.db"))
    with TestClient(app) as client:
        with client.websocket_connect("/ws/dashboard") as websocket:
            response = client.post(
                "/api/report",
                json={
                    "text": "The road is damaged and unsafe near our village school.",
                    "location": "Guntur",
                    "language": "English",
                },
            )
            assert response.status_code == 200
            report = response.json()
            assert report["report_id"] == 1
            assert websocket.receive_json() == {
                "type": "report_created",
                "report": report,
            }

        dashboard_response = client.get("/api/dashboard")
        dashboard = dashboard_response.json()
        assert dashboard["selected_country"] == "All BRICS"
        assert dashboard["metrics"]["citizen_requests"] == 5807
        assert dashboard["recent_reports"][0]["report_id"] == 1

    with TestClient(app) as restarted_client:
        persisted_dashboard = restarted_client.get("/api/dashboard").json()
        assert persisted_dashboard["recent_reports"][0]["report_id"] == 1

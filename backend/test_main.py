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
        assert dashboard["metrics"]["citizen_requests"] == 12487
        assert dashboard["metrics"]["infrastructure_gaps"] == 387
        assert dashboard["recent_reports"][0]["report_id"] == 1

    with TestClient(app) as restarted_client:
        persisted_dashboard = restarted_client.get("/api/dashboard").json()
        assert persisted_dashboard["recent_reports"][0]["report_id"] == 1

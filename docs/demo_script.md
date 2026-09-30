# CivicPulse demo script

1. Open **Citizen report** and point out that residents can submit text in
   multiple languages or tap **Speak** to dictate. The browser/device requests
   microphone permission and streams recognized words into the report box.
2. Select **Telugu example** or submit `మా గ్రామంలో తాగునీటి సమస్య ఉంది.` to demonstrate Telugu detection,
   the included sample translation, water classification, and a transparent
   priority score.
3. Show the score inputs and explanation rather than treating the score as an
   unexplained AI answer.
4. Open **Government** to show illustrative request totals, infrastructure
   hotspots, priority areas, and project recommendations. Keep the dashboard
   open, submit a second report, and show its report event appear in the latest
   reports list without manually refreshing.
5. Emphasize that the dashboard metrics and investment estimates are sample
   data, and the scoring model is a prototype—not an official government
   allocation formula.

## Demo report

```text
మా గ్రామంలో తాగునీటి సమస్య ఉంది.
```

Expected demo interpretation:

```text
Language: Telugu
Category: Water
Location: Guntur
Severity: High or Critical
Recommendation: Prioritize drinking-water infrastructure improvements
```

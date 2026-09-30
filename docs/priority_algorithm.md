# CivicPulse prototype priority model

This is an explainable **prototype scoring model**, not an official government
allocation formula. Its output is a decision-support signal and must not be used
as the sole basis for public investment decisions.

```text
Priority Score =
    Citizen Demand      × 0.30
  + Infrastructure Gap  × 0.25
  + Population Impact   × 0.20
  + Urgency             × 0.15
  + Investment Gap      × 0.10
```

Each input is normalized to the range 0–100. The score is rounded to one decimal
place, then assigned a display band:

For the example values `82, 72, 68, 90, 81`, the weighted sum is **77.8**
(`24.6 + 18.0 + 13.6 + 13.5 + 8.1`), which maps to **High**. This arithmetic
correction is intentional; it follows the specified weights.

| Score | Prototype band |
|---:|---|
| 0–39.9 | Low |
| 40–69.9 | Medium |
| 70–84.9 | High |
| 85–100 | Critical |

The API returns the five input values, weighted score, band, and a plain-language
contribution explanation. The initial demo uses seeded values and transparent
keyword rules; it does not call an LLM or infer an official budget decision.

Before real use, define and validate normalization against representative,
consented local data; assess language and demographic bias; document provenance
and uncertainty; and retain human review and appeal paths.

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
contribution explanation. The demo calculates each input from its joined sample
datasets:

- **Citizen demand:** requests for this country/category/region relative to the
  largest seeded request count for that category in the selected country;
  saved submissions add to the region's count.
- **Infrastructure gap:** `100 - index` for the matching service, using the
  region's index (for example, road index for Roads).
- **Population impact:** estimated affected population relative to a regional
  demographic threshold of the smaller of 10% of the vulnerable population or
  3% of total population; capped at 100.
- **Urgency:** Low 25, Medium 50, High 75, Critical 100, derived from the
  severity label.
- **Investment gap:** uncommitted share of the matching illustrative
  investment-plan amount (`(planned - committed) / planned × 100`); 50 when no
  category-matched plan exists.

The datasets are synthetic and the language/category rules are deterministic;
the prototype does not call an LLM, connect to official budget records, or infer
an official budget decision. See the project README for additional production
gaps.

Before real use, define and validate normalization against representative,
consented local data; assess language and demographic bias; document provenance
and uncertainty; and retain human review and appeal paths.

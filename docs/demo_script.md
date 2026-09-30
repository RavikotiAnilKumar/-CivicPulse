# CivicPulse demo script

## BRICS theme: Innovation

Frame the demo as civic innovation for the public good: help policymakers
listen to community needs, combine those signals with regional context, and
compare explainable project suggestions across BRICS countries. Emphasize
human review and synthetic demo data; do not present suggestions as adopted
plans or proven development outcomes.

1. Open **Citizen report**. Select a country and one of its configured demo
   regions. Explain that voice capture uses browser/device speech recognition.
2. Submit `మా గ్రామంలో తాగునీటి సమస్య ఉంది.` with India / Guntur, or enter
   `Falta água potável no meu bairro.` with Brazil / Bahia, to show script or
   keyword-based language detection and issue classification.
3. Show the score inputs and the regional infrastructure and investment-plan
   values used to explain the score. The exact Telugu example is the only
   sentence with a translated English equivalent in this prototype.
4. Open **Government** and switch between **All BRICS countries** and an
   individual country. Show request aggregates, schematic regional hotspots,
   and ranked project suggestions.
5. Keep the dashboard open, submit another report, and show the WebSocket
   update without manually refreshing.
6. Emphasize that all country data, population estimates, infrastructure
   indices, request volumes, and investment plans are synthetic demo data.
   Messaging-provider ingestion, production translation, and official data
   connectors are not implemented.

## Demo report

```text
మా గ్రామంలో తాగునీటి సమస్య ఉంది.
```

Expected demo interpretation:

```text
Language: Telugu
Category: Water
Country / region: India / Guntur
Severity: High or Critical (sample baseline may raise urgency)
Recommendation: Review a data-linked regional water investment priority
```

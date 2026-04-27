# The Story: 5-Act Visual Narrative

> Every chart here exists to answer one of the five questions.
> The data is the evidence. The story is the argument.

---

## ACT 1 — WHO IS ACTUALLY IN HERE?

**The Headline Number:** Percentage of current jail population that is legally innocent (pretrial).

### Chart 1A: The Innocence Bar
- **Type:** Stacked horizontal bar, one bar per jurisdiction
- **Stacks:** Pretrial (legally innocent) vs. Post-conviction (sentenced)
- **Color:** Pretrial = orange/amber. Sentenced = gray.
- **What it says:** Most people in these facilities have not been convicted of anything.
- **Data source:** `mv_innocence_by_jurisdiction`

### Chart 1B: The $500 Wall
- **Type:** Dot plot / lollipop chart
- **X-axis:** Bail amount buckets ($0-$500, $500-$1k, $1k-$5k, $5k+)
- **Y-axis:** Number of pretrial detainees
- **Annotation:** "X people are in a cage right now for under $500 bail."
- **Data source:** `innocence.sql` Part 1

### Chart 1C: Charge Mix — What Are They Actually In Here For?
- **Type:** Treemap, colored by category
- **Categories:** Violent (red), Property (yellow), Drug/Addiction (purple), Poverty-Linked (blue), Other (gray)
- **What it says:** The majority of pretrial detainees are here for non-violent charges.
- **Data source:** `innocence.sql` Part 2

---

## ACT 2 — WHAT DOES IT COST THEM?

**The Headline Number:** Average work-days to buy freedom in the poorest ZIP codes.

### Chart 2A: The Bail Gap Heatmap
- **Type:** Choropleth map by ZIP code
- **Color scale:** White (low bail gap) → Dark red (high bail gap)
- **Overlay:** Bubble size = number of intake bookings from that ZIP
- **Tooltip:** ZIP, Median Income, Avg Bail Set, Work-Days to Freedom, Eviction Rate
- **What it says:** The ZIPs sending the most people to jail are the same ZIPs where bail is most unaffordable.
- **Data source:** `mv_bail_gap_by_zip`, `bail_gap.sql` Part 3

### Chart 2B: The $500 Question — Side by Side
- **Type:** Grouped bar chart
- **Groups:** Each jurisdiction
- **Bars:** Work-days to pay $500 bail / $1,000 bail / $5,000 bail
- **Benchmark line:** Federal minimum wage equivalent
- **What it says:** Same dollar amount. Completely different number of days of your life.
- **Data source:** `bail_gap.sql` Part 2

### Chart 2C: The Sankey — From Arrest to Resolution
- **Type:** Sankey / Alluvial diagram
- **Nodes left to right:**
  ```
  Arrested
    → [Charged] → [Not Charged / Dismissed immediately]
  Charged
    → [Bail Set - Cash] → [ROR / No Cash] → [Remand]
  Bail Set - Cash
    → [Bail Paid - Released] → [Bail Not Paid - Detained]
  Detained
    → [0-7 days] → [8-30 days] → [1-3 months] → [3-12 months] → [1+ year]
  Resolution
    → [Guilty Plea] → [Trial Conviction] → [Acquitted] → [Dismissed] → [Nolle Prosequi]
  ```
- **Color:** Flows from pretrial detention → Guilty Plea should be a distinct color (red)
  to show the coercion pipeline
- **What it says:** Follow the people who can't make bail. Watch where they end up.
  Most of them plead guilty. The longer they're detained, the higher that rate climbs.
- **Data source:** `plea_pressure.sql` Part 1

### Chart 2D: The Plea Trap — Guilty Plea Rate by Time in Cage
- **Type:** Line chart
- **X-axis:** Detention length buckets (0-7 days, 8-30, 1-3mo, 3-6mo, 6-12mo, 1yr+)
- **Y-axis:** Guilty plea rate (%)
- **Lines:** One per jurisdiction, plus a combined average
- **Expected shape:** Upward curve — the longer someone sits, the more likely they plead guilty
- **Annotation at inflection point:** "After X days in pretrial detention,
  more than Y% of people plead guilty — including those who will be acquitted at trial."
- **Data source:** `plea_pressure.sql` Part 1

---

## ACT 3 — ADDICTION BEHIND BARS

**The Headline Number:** People locked up for possession vs. people who got treatment.

### Chart 3A: Addiction Arrests Over Time
- **Type:** Area chart
- **X-axis:** Year (2018-present)
- **Y-axis:** Addiction-related bookings
- **Overlay:** Treatment facility capacity in same jurisdiction (if available)
- **What it says:** The gap between people who need treatment and people who get it is filled by cages.
- **Data source:** `addiction.sql` Part 1

### Chart 3B: The Cycle — Repeat Bookings for Addiction
- **Type:** Chord diagram or repeat-booking bar chart
- **Shows:** How many people appear 2x, 3x, 4x, 5+ times on possession charges
- **What it says:** This is what happens when you treat addiction as crime.
  No treatment = revolving door. The system doesn't break the cycle. It IS the cycle.
- **Data source:** `addiction.sql` Part 3

### Chart 3C: Possession by Neighborhood Income
- **Type:** Scatter plot
- **X-axis:** ZIP median income
- **Y-axis:** Addiction-related arrest rate per 1,000 residents
- **Color:** % of arrests that result in pretrial detention
- **What it says:** Addiction exists everywhere. Arrests for addiction happen in the poorest places.
- **Data source:** `addiction.sql` Part 2

---

## ACT 4 — THE CONDITIONS INSIDE

**The Headline Number:** Deaths in custody per 1,000 detainees. Percentage of those legally innocent.

### Chart 4A: Capacity vs. Population — Overcrowding Timeline
- **Type:** Area chart with threshold line
- **X-axis:** Date (90 days)
- **Y-axis:** Population as % of rated capacity
- **Red line:** 100% capacity
- **Shaded zone above red:** People living in conditions that exceed legal limits
- **One panel per major facility:** Rikers, LA County, DC Jail, Baltimore City
- **Data source:** `conditions.sql` Part 3

### Chart 4B: Deaths in Custody
- **Type:** Dot plot / timeline
- **Each dot:** One death. Size = days detained before death. Color = conviction status.
- **Filter:** Deaths of legally innocent people (pretrial)
- **What it says:** These people were never convicted. They died waiting.
- **Data source:** `conditions.sql` Part 2 + Marshall Project data

### Chart 4C: Use of Force vs. Overcrowding
- **Type:** Scatter / dual-axis
- **X-axis:** Capacity utilization %
- **Y-axis:** Use of force incidents per 100 detainees
- **What it says:** The more overcrowded, the more violence. More violence against people
  who haven't been convicted of anything.
- **Data source:** `conditions.sql` Part 1

---

## ACT 5 — DID REFORM HELP?

**The Headline Question:** Maryland 2017 — real change, or just a different mechanism?

### Chart 5A: Before vs. After Reform — The Three Numbers
- **Type:** Before/After comparison (3 KPI cards side by side)
  ```
  Cash Bail Rate     Remand Rate      Avg Pretrial Days
  Pre:  XX%          Pre:  XX%        Pre:  XX days
  Post: XX%          Post: XX%        Post: XX days
  ```
- **The question it answers:** If cash bail went down but remand went up by the same amount,
  the system adapted. Reform changed the name, not the outcome.
- **Data source:** `md_reform.sql` Part 1

### Chart 5B: Reform Impact by Income — Who Did It Actually Help?
- **Type:** Grouped bar chart
- **Groups:** Income tiers (Under $35k, $35-55k, $55-80k, $80k+)
- **Bars:** Pre-reform pretrial rate vs. Post-reform pretrial rate
- **What it says:** Reform often helps people with more resources to navigate the new system.
  If the poorest ZIPs saw no improvement, reform failed the people who needed it most.
- **Data source:** `md_reform.sql` Part 3

### Chart 5C: The Monthly Trend — Reform in Real Time
- **Type:** Line chart with reform date marked by a vertical line
- **X-axis:** Month (July 2015 - June 2019)
- **Lines:** Pretrial detention rate, Cash bail rate, Remand rate
- **Vertical marker:** July 1, 2017 — "MD Bail Reform Takes Effect"
- **What it says:** The exact moment reform hit. Did the lines move?
  Which ones? And did they stay moved?
- **Data source:** `md_reform.sql` Part 2

---

## Dashboard Layout (Power BI / Tableau)

```
┌─────────────────────────────────────────────────────────────┐
│  WHO IS IN JAIL — AND WHY?                      [Filters]   │
│  Jurisdiction: [ALL ▼]  Year: [2023 ▼]  Charge: [ALL ▼]   │
├──────────────┬──────────────┬──────────────┬────────────────┤
│  LEGALLY     │  AVG DAYS    │  HELD UNDER  │  AVG WORK-DAYS │
│  INNOCENT    │  PRETRIAL    │  $1,000 BAIL │  TO FREEDOM    │
│  XX%         │  XX days     │  XX,XXX ppl  │  XX days       │
├──────────────┴──────────────┴──────────────┴────────────────┤
│                    BAIL GAP HEATMAP                          │
│              [ZIP-level choropleth map]                      │
├──────────────────────────┬──────────────────────────────────┤
│     CHARGE MIX           │      PLEA TRAP                   │
│     [Treemap]            │      [Line: guilty plea rate]    │
├──────────────────────────┴──────────────────────────────────┤
│                      THE SANKEY                             │
│         Arrest → Bail → Detention → Resolution             │
├──────────────────────────┬──────────────────────────────────┤
│   ADDICTION CYCLE        │   OVERCROWDING TIMELINE          │
│   [Repeat bookings]      │   [Area chart vs. capacity]      │
└──────────────────────────┴──────────────────────────────────┘
```

---

## Color Language (consistent across all charts)

| Meaning | Color |
|---|---|
| Legally innocent / pretrial | `#E8832A` (amber) |
| Violent charges | `#C0392B` (deep red) |
| Poverty-linked charges | `#2980B9` (blue) |
| Addiction-related charges | `#8E44AD` (purple) |
| Released / resolved fairly | `#27AE60` (green) |
| Guilty plea (potential coercion) | `#E74C3C` (bright red) |
| Overcrowding zone | `#C0392B` (deep red) with opacity |
| Background / neutral | `#2C3E50` (dark) / `#ECF0F1` (light) |

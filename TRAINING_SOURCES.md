# TRAINING_SOURCES.md

> Educational, non‑medical guidance sources behind the app's training, fueling,
> and safety logic. All numeric targets (training phases, fueling g/h, hydration
> mL/h, long‑run caps) are **configurable defaults**, not medical prescriptions.
> The app surfaces a disclaimer prompting users to consult a physician and,
> ideally, a qualified coach or registered sports dietitian. These are reputable
> coaching / sports‑science / safety organizations, not national governing‑body
> curricula; where sources conflict, the app defaults to the conservative,
> finish‑safely option and keeps it configurable.

## Periodization & training structure

- **Joe Friel — "K.I.S.S. Periodization"** — https://joefrieltraining.com/kiss-periodization/
  Six sequential season periods (Prep ~2–4 wk, Base ~12 wk, Build ~8–9 wk, Peak
  ~1–2 wk, Race ~1 wk, Transition). Informs the macro plan: for a ~9‑month
  first‑timer, a short prep, a long aerobic base, a race‑specific build, and a
  short peak/taper.
- **Joe Friel — "Build Period Overview"** — https://joefrieltraining.com/build-period-overview/
  For ultra‑distance events, volume may rise while intensity stays moderate;
  "hard days hard, easy days easy." Drives Build‑phase load logic so intensity
  isn't over‑prescribed for a finisher.
- **Joe Friel — "Recovery Week Design"** — https://joefrieltraining.com/recovery-week-design/
  Insert a recovery week after ~2–5 weeks of hard training (commonly a **3:1**
  build:recovery cadence). Recovery weeks are not optional. Drives automatic
  recovery‑week placement and the "don't restore volume into a recovery week"
  rule.
- **The Triathlete — "20‑Week Ironman Plan (First‑Timers)"** — https://thetriathlete.co.uk/training-plans/20-week-ironman-training-plan-first-timers/
  Cross‑check for the macrocycle→meso/microcycle model and phase durations; the
  9‑month window allows a longer base than a typical 20‑week plan. *(Medium
  confidence; coach authority.)*

## Run training, bricks & taper

- **220 Triathlon — "Ironman run training: how important is the weekly long run?"** — https://www.220triathlon.com/training/long-distance/ironman-run-training-how-important-is-the-weekly-long-run
  Cap training long runs at ~**18–20 miles**; the race marathon is run on
  accumulated bike fatigue and longer runs carry high injury/recovery cost. Sets
  the app's default (configurable) long‑run cap. **No full‑marathon training run.**
- **TrainingPeaks — "Ultimate Full‑Distance Triathlon Training Guide"** — https://www.trainingpeaks.com/guides/ironman-training/
  Brick (bike‑to‑run) workouts rehearse pacing/nutrition/running on tired legs;
  introduce ~12–16 weeks out (start as small as a 1‑mile run off the bike) and
  progress. *(This guide also allows training runs up to 26.2 mi — a direct
  conflict with the cap above; the app defaults to the conservative cap but
  exposes it as configurable.)*
- **220 Triathlon — "Tapering: why it's important…"** — https://www.220triathlon.com/training/tapering-why-it-s-important-and-what-you-should-do-the-week-before-your-triathlon
  Cut volume ~**30–50%** (≈30% for a 3‑week taper, 50% for 2 weeks) while
  retaining intensity; run gets the longest taper. Drives the taper module's
  default volume‑reduction curve.

## Fueling & hydration (configurable targets)

- **GSSI (ACSM‑aligned) — "Dietary Carbohydrate and the Endurance Athlete"** — https://www.gssiweb.org/sports-science-exchange/article/dietary-carbohydrate-and-the-endurance-athlete-contemporary-perspectives
  ~**30–60 g carb/h** for ~1–2.5 h sessions; up to ~**90 g/h** for >2.5–3 h;
  above 60 g/h use glucose+fructose. Defines the duration‑banded carb slider.
- **ISSN Position Stand: Nutrient Timing (Kerksick et al.)** — https://pmc.ncbi.nlm.nih.gov/articles/PMC5596471/
  In‑session carbohydrate matters reliably only past ~**60–90 min**. Sets the
  threshold at which in‑session fueling prompts begin.
- **IOC Consensus Statement on Sports Nutrition (2010)** — https://www.tandfonline.com/doi/full/10.1080/02640414.2011.619349
  "Train the gut": rehearse race‑day intake in training. Drives the core
  "practice your race‑day fueling, never experiment on race day" prompts.
- **ACSM Position Stand: Exercise and Fluid Replacement** — https://www.khsaa.org/sportsmedicine/heat/exerciseandfluidreplacement.pdf
  Keep body‑mass loss under ~2%; individualize to measured sweat rate. Makes
  hydration a per‑athlete configurable target. *(Medium confidence; primary MSSE
  text paywalled.)*
- **AAFP — "Exercise‑Associated Hyponatremia" (Wilderness Medical Society)** — https://www.aafp.org/pubs/afp/issues/2021/0215/p252.html
  **Overdrinking** is the primary cause of EAH; "drink to thirst" is the safest
  default. Drives the app's **over‑hydration warning** (not just dehydration) and
  bounded hydration ranges.

## Open‑water & environmental safety (hard rules)

- **U.S. Masters Swimming — "Open Water Swimming 101"** — https://www.usms.org/fitness-and-training/guides/open-water-swimming-101
  **Never swim alone**; sight ("alligator eyes") every ~5–10 strokes; build cold
  tolerance gradually; bright cap + tow float; properly fitted wetsuit. Sources
  the non‑negotiable "never swim alone" rule and open‑water equipment checklist.
- **USA Triathlon — "Winning in the Water: Top Tips for the Open Water Swim"** — https://www.usatriathlon.org/articles/training-tips/winning-open-water-top-tips
  Enter gradually, run a pre‑swim conditions check (temperature, wind, traffic,
  tides, currents). Drives the graded open‑water progression + pre‑swim checklist.
- **National Weather Service — "Lightning Safety"** — https://www.weather.gov/wrn/summer-lightning-sm
  "When thunder roars, go indoors" — exit water immediately and wait 30 min after
  the last clap. A **hard stop** for any weather‑aware water‑session feature
  (Release 3).

---

**Caveats.** Specific numbers (phase weeks, 3:1 cadence, 18–20 mi long‑run cap,
taper %) rest on coach authority (Friel is the most‑cited long‑course
periodization source). All fueling/hydration numbers are individualized,
configurable ranges — **not medical advice**. The one explicit source conflict
(long‑run cap 18–20 mi vs up to 26.2 mi) is resolved toward the conservative
value for finish‑safely first‑timers and kept configurable.

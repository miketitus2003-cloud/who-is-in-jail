# Who Is in Jail — And Why?

> *A data investigation into the people the system was never designed to protect.*

---

When I was 13 years old, the police knocked on my door at 4:30 in the morning on a school night.
They had pictures pulled from my mother's Facebook account.
They treated me like a criminal for something I had nothing to do with.

I was lucky. My parents were home. They were educated. They knew their rights.
They told the police they could not search my room.

Most people don't have that.
Most kids don't have that.
And the system knows it.

---

## What This Project Is

This is not a school project. This is not a portfolio piece.

This is a data investigation into one of the most important civil rights questions in America:

**Who is actually sitting in jail and why?**

Not who the police report says belongs there.
Not the story the system tells about itself.
The real numbers. The real conditions. The real human cost.

---

## What the Data Shows

The majority of people in America's largest jails Rikers Island, LA County Jail,
DC Jail, Baltimore City Detention Center — have not been convicted of anything.

They are **legally innocent**. They are there because they are poor.

A person with money gets arrested and goes home the same night.
A person without money gets arrested and sits in a cage — sometimes for months,
sometimes for years waiting for a trial that may never come, or that eventually
clears them of everything.

While they wait, they lose their job. Their apartment. Their children.
Then they're offered a deal: plead guilty right now and go home today.
Or stay here and wait and risk a worse sentence if you lose.

Most people take the deal.

Not because they're guilty.
Because the alternative is unbearable.

**This is not justice. This is coercion by poverty.**

---

## Addiction Is Not a Crime

A massive portion of the people in these facilities are there for drug possession.
Not dealing. Not violence. Possession.

Possession means addiction in most cases.
Addiction is a medical condition.

We lock people up for it instead of treating them.
Then we give them a criminal record that makes it nearly impossible to get housing,
employment, or stability when they get out which makes relapse more likely, not less.

The data shows this. The data shows the cycle. This project makes that cycle visible.

---

## The Conditions Inside

Rikers Island has been under federal investigation for years.
People have died there waiting for trial — on charges that were later dropped.
The violence, the medical neglect, the solitary confinement of people who
haven't been convicted of anything these aren't accidents. This is the system.

LA County Jail is one of the largest jail systems in the world.
It has a documented history of deputy gangs, excessive force, and deaths in custody.

These are not edge cases.
This is the system operating exactly as it was designed — against people
who have no power to push back.

---

## The Five Questions This Project Answers

1. **How many people in these jails right now have never been convicted of anything?**
2. **How many people pleaded guilty to something they didn't do because they couldn't afford to wait?**
3. **How many people are locked up for addiction instead of getting treatment?**
4. **How much money separates someone who goes home from someone who loses everything?**
5. **Did the 2017 Maryland Bail Reform actually help — or did the system just adapt?**

---

## Project Structure

```
who-is-in-jail/
├── etl/
│   ├── sources.py         # All API source configs — verified against live APIs
│   ├── extract.py         # Paginated Socrata + ArcGIS extractor with rate limiting
│   ├── ethics.py          # PII hashing, age bucketing — runs before anything hits disk
│   ├── census.py          # US Census ACS socioeconomic enrichment
│   ├── vera_loader.py     # Vera Institute county CSV — the historical backbone
│   ├── db_loader.py       # Load Parquet → PostgreSQL star schema
│   └── pipeline.py        # Master orchestrator — runs steps 1-7 in order
├── sql/
│   ├── schema/ddl.sql     # Star schema — the full database architecture
│   ├── queries/
│   │   ├── innocence.sql      # Who is legally innocent but still caged?
│   │   ├── plea_pressure.sql  # The coercion built into long pretrial detention
│   │   ├── addiction.sql      # Drug possession: health crisis treated as crime
│   │   ├── bail_gap.sql       # Work-days-to-freedom by ZIP code
│   │   ├── md_reform.sql      # Did the 2017 MD reform actually change anything?
│   │   └── conditions.sql     # Deaths, overcrowding, use of force inside
│   └── seeds/
│       └── charge_taxonomy.sql  # How charges are classified: violent/poverty/addiction
├── viz/
│   └── story.md           # The 5-act narrative: what to show and how
├── docs/
│   ├── ETHICS.md          # Why this data was handled the way it was
│   └── SOURCES.md         # Every data source, what it shows, and where to get it
├── data/                  # .gitignored — no raw data ever committed
├── .env.example
└── requirements.txt
```

---

## How to Run It

```bash
# 1. Clone and set up environment
git clone https://github.com/miketitus2003-cloud/who-is-in-jail
cd who-is-in-jail
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt

# 2. Add your API keys
cp .env.example .env
# Edit .env with your Socrata app tokens and Census API key

# 3. Set up the database
psql -U postgres -c "CREATE DATABASE jail_data;"
psql -U postgres -d jail_data -f sql/schema/ddl.sql
psql -U postgres -d jail_data -f sql/seeds/charge_taxonomy.sql

# 4. Run the pipeline
python etl/pipeline.py

# 5. Run the analysis queries
psql -U postgres -d jail_data -f sql/queries/innocence.sql
```

---

## The People Behind the Numbers

Every row in this dataset is a person.

Someone's parent. Someone's child. Someone who woke up one morning
and by that night was sitting in a cage not because they were convicted of anything,
but because they were poor, or sick, or in the wrong place, or the police
had a story that wasn't fully true.

This project exists to make that visible.
Because the first step to changing something is being honest about what it is.

*— Michael*

---

## Data Sources

See [docs/SOURCES.md](docs/SOURCES.md) for every source, what it proves, and how to access it.

## Ethics

See [docs/ETHICS.md](docs/ETHICS.md) for how this sensitive data was handled and why.

# Why I Built This — And How I Handled the Data

---

## Where This Comes From

I was 13 years old when the police knocked on my door at 4:30 in the morning on a school night.

They had pictures pulled from my mother's Facebook account. They treated me like a criminal
for something I had nothing to do with.

I was lucky. My parents were home. They were educated enough to know their rights.
They told the police they could not search my room. The officers left.

That night, nothing happened to me.

But I never forgot what it felt like to be 13 years old, still in pajamas, looking at police
officers who had already decided I was guilty. I never forgot the way they looked at me.
And I never stopped thinking about the kids who didn't have parents at home when that knock came.
The kids who didn't know they could say no. The adults who couldn't say no either —
because no one ever taught them they had that right, or because the officers didn't care.

That's what this project is about.

---

## What I'm Trying to Show

Not everyone in jail is a heartless criminal.

That sounds simple. It's not — because the system is built on the opposite assumption.
The assumption that everyone who gets arrested belongs there. That the police always
have the story right. That if you're locked up, you probably did something.

The data says otherwise.

The majority of people in America's largest jails — Rikers Island, LA County Jail,
DC Jail, Baltimore City Detention Center — have not been convicted of anything.
They are legally innocent. They are sitting in cages because they are poor.

A person with money gets arrested and goes home the same night.
A person without money gets arrested and sits — sometimes for months, sometimes for years —
waiting for a trial that might never come, or that eventually clears them of everything.

While they wait, they lose their job. Their apartment. Custody of their children.
Then they're offered a deal: plead guilty right now and go home today.
Or stay here and wait — and risk a worse sentence if you lose at trial.

Most people take the deal. Not because they're guilty.
Because the alternative is unbearable.

This is coercion dressed up as due process.

---

## Addiction Is Not a Crime

A massive portion of the people in these facilities are there for drug possession.
Not dealing. Not violence. Possession — which in most cases means addiction.

Addiction is a medical condition.

We respond to it with cages and criminal records. Then we wonder why recovery is so hard.
When you get out with a drug conviction, you can't get certain jobs. You can't get
federal housing assistance. You can't get many professional licenses. The criminal
record follows you everywhere — and everywhere it goes, it makes stability harder.

Harder stability means higher relapse risk.
Higher relapse risk means re-arrest.
Re-arrest means back in a cage.

The data shows this cycle clearly. The same people appear in these records
over and over, on the same charges. Not because they're bad people.
Because they needed treatment and got handcuffs instead.

---

## The Conditions

Rikers Island has been under federal oversight for years because of the violence,
the medical neglect, the deaths, the use of solitary confinement on people who haven't
been convicted of anything. People have died at Rikers waiting for trial —
on charges that were later dropped. The city has spent years promising to close it.
It's still open.

LA County Jail is one of the largest jail systems in the world. It has documented
deputy gangs operating inside — groups of officers with matching tattoos who
beat detainees and are protected by the institution. People have died there.
People have been beaten there while legally innocent.

These are not isolated incidents. They are what happens when you build a system
designed to warehouse poor people and give it almost no accountability.

---

## How I Handled the Data

The people in this dataset did not consent to being analyzed.

They're in here because they were arrested — not because they chose to be part of a study.
That matters. It shapes every technical decision I made.

**No names, ever.**
Every individual identifier in the source data is replaced with a one-way cryptographic
hash before any data touches a database or file system. The hash is irreversible.
You cannot get from the hash back to a name. The same person across multiple bookings
produces the same hash, so I can analyze patterns over time — without ever storing
who they are.

**No exact ages.**
Age is replaced with a 10-year bucket (18-24, 25-34, etc.) at the moment of ingestion —
before anything is saved. Exact age combined with gender, charge, ZIP code, and date
is enough to re-identify someone in a small population. The bucket removes that risk
while keeping every analytical insight that matters: are young adults most affected
by cash bail? Are elderly people dying pretrial? Those questions are still answerable.

**No data that wasn't needed.**
Some source APIs include fields I didn't need: partial social security numbers,
employer records, physical descriptions. Those fields are excluded at extraction time
and never enter the pipeline.

**The raw data stays raw.**
No individual-level data is published in this repository. What you see here
are aggregate outputs, query logic, and anonymized analysis. The only things
committed to this repo are code and findings — not records of real people.

---

## What This Data Cannot Do

This project does not:
- Identify any individual
- Make predictions about whether specific people will commit crimes
- Recommend who should or shouldn't be detained

This is descriptive analysis of structural patterns. It shows that the system
produces certain outcomes at scale. It does not score individuals.

There is a difference between "ZIP code X produces disproportionate pretrial detention"
and "person from ZIP code X is more likely to reoffend." This project only makes
the first kind of claim. The second kind is how you build a tool of oppression.
I'm not building that.

---

## What I Want People to Take Away

The police don't always have the story right.

The system is not neutral. It is not blind. It does not weigh everyone equally.

It lands heaviest on the people with the least power to push back:
people without money for bail, without lawyers who have time for them,
without parents who know their rights, without neighborhoods that get
the benefit of the doubt.

The data in this project is one way of making that visible.
Visible is the first step toward accountable.

*— Michael*

-- ============================================================
-- WHO IS IN JAIL — AND WHY?
-- Charge Taxonomy Seed Data
-- ============================================================
-- This is where the argument is made in data form.
--
-- Every charge below is classified. The classification is deliberate.
-- is_poverty_linked = TRUE means: this law exists to punish people
--   for being poor. Sleeping in public. Riding the train without $2.90.
--   Standing outside too long. These are not crimes against anyone.
--   They are poverty, treated as criminality.
--
-- is_addiction_related = TRUE means: this person needed a doctor,
--   not a cage. Possession is not predatory. Addiction is medical.
--   We lock people up for it and call it justice.
--
-- The taxonomy is documented and auditable. If you disagree
-- with a classification, the reasoning is here to challenge.
-- ============================================================

TRUNCATE dim_charges RESTART IDENTITY CASCADE;

INSERT INTO dim_charges
    (charge_description, charge_class, charge_category,
     is_violent, is_poverty_linked, is_addiction_related,
     jurisdiction, penal_law_section)
VALUES

-- ── VIOLENT CHARGES ───────────────────────────────────────────────────────────
('Murder / Homicide',                   'Felony A', 'Violent',  TRUE,  FALSE, FALSE, 'ALL',  'PL 125'),
('Manslaughter',                        'Felony B', 'Violent',  TRUE,  FALSE, FALSE, 'ALL',  'PL 125'),
('Rape / Sexual Assault',               'Felony B', 'Violent',  TRUE,  FALSE, FALSE, 'ALL',  'PL 130'),
('Robbery (Armed)',                     'Felony B', 'Violent',  TRUE,  FALSE, FALSE, 'ALL',  'PL 160'),
('Robbery (Unarmed)',                   'Felony C', 'Violent',  TRUE,  FALSE, FALSE, 'ALL',  'PL 160'),
('Assault (Felony)',                    'Felony C', 'Violent',  TRUE,  FALSE, FALSE, 'ALL',  'PL 120'),
('Assault (Misdemeanor)',               'Misd A',   'Violent',  TRUE,  FALSE, FALSE, 'ALL',  'PL 120'),
('Kidnapping',                          'Felony A', 'Violent',  TRUE,  FALSE, FALSE, 'ALL',  'PL 135'),
('Arson',                               'Felony B', 'Violent',  TRUE,  FALSE, FALSE, 'ALL',  'PL 150'),
('Burglary (Occupied)',                 'Felony B', 'Violent',  TRUE,  FALSE, FALSE, 'ALL',  'PL 140'),
('Domestic Violence - Assault',         'Misd A',   'Violent',  TRUE,  FALSE, FALSE, 'ALL',  'PL 120'),
('Weapons Possession (w/ intent)',      'Felony C', 'Violent',  TRUE,  FALSE, FALSE, 'ALL',  'PL 265'),

-- ── PROPERTY CRIMES ───────────────────────────────────────────────────────────
('Grand Larceny (over $1,000)',         'Felony E', 'Property', FALSE, FALSE, FALSE, 'ALL',  'PL 155'),
('Grand Larceny (over $3,000)',         'Felony D', 'Property', FALSE, FALSE, FALSE, 'ALL',  'PL 155'),
('Identity Theft',                      'Felony E', 'Property', FALSE, FALSE, FALSE, 'ALL',  'PL 190'),
('Fraud / Forgery',                     'Felony E', 'Property', FALSE, FALSE, FALSE, 'ALL',  'PL 170'),
('Auto Theft',                          'Felony D', 'Property', FALSE, FALSE, FALSE, 'ALL',  'PL 155'),
('Burglary (Unoccupied)',               'Felony C', 'Property', FALSE, FALSE, FALSE, 'ALL',  'PL 140'),
('Criminal Mischief',                   'Misd A',   'Property', FALSE, FALSE, FALSE, 'ALL',  'PL 145'),

-- ── DRUG CHARGES — ADDICTION, NOT CRIME ──────────────────────────────────────
-- These people needed treatment. They got a cage.
-- Note: Distribution/Sale is different from possession — classified separately.
('Criminal Possession Controlled Substance 7th', 'Misd A', 'Drug', FALSE, FALSE, TRUE, 'NYC', 'PL 220.03'),
('Criminal Possession Controlled Substance 5th', 'Felony D', 'Drug', FALSE, FALSE, TRUE, 'NYC', 'PL 220.06'),
('Criminal Possession Controlled Substance 4th', 'Felony C', 'Drug', FALSE, FALSE, TRUE, 'NYC', 'PL 220.09'),
('Possession of Drug Paraphernalia',    'Infraction','Drug',   FALSE, FALSE, TRUE,  'ALL',  NULL),
('Possession of Marijuana (small amt)', 'Infraction','Drug',   FALSE, FALSE, TRUE,  'ALL',  NULL),
('Possession of Marijuana (felony)',    'Felony E', 'Drug',    FALSE, FALSE, TRUE,  'ALL',  NULL),
('Possession of Heroin',                'Felony D', 'Drug',    FALSE, FALSE, TRUE,  'ALL',  NULL),
('Possession of Cocaine',               'Felony D', 'Drug',    FALSE, FALSE, TRUE,  'ALL',  NULL),
('Possession of Fentanyl',              'Felony C', 'Drug',    FALSE, FALSE, TRUE,  'ALL',  NULL),
('Possession of Methamphetamine',       'Felony D', 'Drug',    FALSE, FALSE, TRUE,  'ALL',  NULL),
('Public Intoxication',                 'Infraction','Drug',   FALSE, FALSE, TRUE,  'ALL',  NULL),
('Driving Under Influence (first)',     'Misd A',   'Drug',    FALSE, FALSE, TRUE,  'ALL',  NULL),
-- Sale/Distribution: different intent, different category
('Criminal Sale Controlled Substance',  'Felony B', 'Drug',    FALSE, FALSE, FALSE, 'NYC',  'PL 220.39'),
('Drug Trafficking',                    'Felony A', 'Drug',    FALSE, FALSE, FALSE, 'ALL',  NULL),

-- ── POVERTY-LINKED CHARGES — CRIMINALIZING BEING POOR ────────────────────────
-- These are not crimes against people. They are laws that punish
-- the act of being visibly poor in public.
-- Every single one of these represents the system treating poverty as criminality.
('Fare Evasion / Theft of Services',    'Infraction','Poverty-Linked', FALSE, TRUE, FALSE, 'NYC', 'PL 165.15'),
('Trespassing (Misdemeanor)',           'Misd B',   'Poverty-Linked', FALSE, TRUE, FALSE, 'ALL',  'PL 140.05'),
('Loitering',                           'Infraction','Poverty-Linked', FALSE, TRUE, FALSE, 'ALL',  NULL),
('Disorderly Conduct',                  'Infraction','Poverty-Linked', FALSE, TRUE, FALSE, 'ALL',  'PL 240.20'),
('Petit Larceny (under $250)',          'Misd A',   'Poverty-Linked', FALSE, TRUE, FALSE, 'ALL',  'PL 155.25'),
('Petit Larceny ($250-$1000)',          'Misd A',   'Poverty-Linked', FALSE, TRUE, FALSE, 'ALL',  'PL 155.25'),
('Panhandling / Aggressive Begging',    'Infraction','Poverty-Linked', FALSE, TRUE, FALSE, 'ALL',  NULL),
('Sleeping in Public / Vagrancy',       'Infraction','Poverty-Linked', FALSE, TRUE, FALSE, 'ALL',  NULL),
('Urinating in Public',                 'Infraction','Poverty-Linked', FALSE, TRUE, FALSE, 'ALL',  NULL),
('Open Container',                      'Infraction','Poverty-Linked', FALSE, TRUE, FALSE, 'ALL',  NULL),
('Criminal Trespass (Housing)',         'Misd B',   'Poverty-Linked', FALSE, TRUE, FALSE, 'ALL',  'PL 140.10'),
-- Failure to pay fines (bench warrants) — jailed for not having money
('Bench Warrant - Failure to Appear',   'Misd A',   'Poverty-Linked', FALSE, TRUE, FALSE, 'ALL',  NULL),
('Failure to Pay Fine',                 'Infraction','Poverty-Linked', FALSE, TRUE, FALSE, 'ALL',  NULL),
('Probation Violation (technical)',     'Misd A',   'Poverty-Linked', FALSE, TRUE, FALSE, 'ALL',  NULL),

-- ── OTHER / ADMINISTRATIVE ────────────────────────────────────────────────────
('Weapons Possession (unlicensed)',     'Felony E', 'Other',   FALSE, FALSE, FALSE, 'ALL',  'PL 265'),
('Resisting Arrest',                    'Misd A',   'Other',   FALSE, FALSE, FALSE, 'ALL',  'PL 205.30'),
('Obstruction of Justice',              'Misd A',   'Other',   FALSE, FALSE, FALSE, 'ALL',  NULL),
('Contempt of Court',                   'Misd A',   'Other',   FALSE, FALSE, FALSE, 'ALL',  NULL),
('Immigration Hold (ICE Detainer)',     'Administrative','Other', FALSE, FALSE, FALSE, 'ALL', NULL),
('Mental Health Hold',                  'Civil',    'Other',   FALSE, FALSE, FALSE, 'ALL',  NULL),
('Unknown / Not Specified',             NULL,       'Other',   FALSE, FALSE, FALSE, 'ALL',  NULL);

-- ── Verification ──────────────────────────────────────────────────────────────
SELECT
    charge_category,
    COUNT(*)            AS total_charges,
    SUM(CASE WHEN is_poverty_linked    THEN 1 ELSE 0 END) AS poverty_linked,
    SUM(CASE WHEN is_addiction_related THEN 1 ELSE 0 END) AS addiction_related,
    SUM(CASE WHEN is_violent           THEN 1 ELSE 0 END) AS violent
FROM dim_charges
GROUP BY charge_category
ORDER BY total_charges DESC;

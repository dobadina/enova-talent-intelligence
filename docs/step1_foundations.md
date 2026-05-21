# Step 1: Project Foundations
## Data Dictionary · Canonical Stage List · Data Quality Issue Log

**Project:** Enova Technologies — Talent Intelligence Analytics  
**Document purpose:** This document is the single source of truth for all data decisions in this project.  
Every table, every field, every cleaning rule, and every canonical value is defined here before any code is written.  
If a decision made in a Python script or SQL view contradicts this document, this document wins.

---

## PART 1: DATA DICTIONARY

A data dictionary is a reference document that describes every table and every field in a dataset.
Think of it as a glossary for the data. It answers three questions for every field:
- What does this field contain?
- What format is it in?
- What are the valid values?

There are nine tables across three source systems.

---

### SYSTEM 1: TalentFlow (ATS — Applicant Tracking System)
> TalentFlow is the fictional name for the system that tracks job applications.
> It is modelled on Greenhouse, which is a real ATS used by many tech companies.
> It stores everything related to recruiting: jobs, candidates, applications, pipeline movement, and offers.

---

#### Table 1: `talentflow_jobs`
One row per job requisition (an approved request to hire someone).

| Field | Data Type | Description | Valid Values / Format |
|---|---|---|---|
| `job_id` | String | Unique identifier for the job requisition | Format: `JOB-001` to `JOB-045` |
| `job_title` | String | The title of the role being hired for | E.g. "Senior Backend Engineer", "Product Manager" |
| `department` | String | Which department owns this role | See Department List below |
| `location` | String | Where the role is based | City name, or "Remote — Europe" |
| `employment_type` | String | Type of employment contract | `full_time`, `contractor`, `part_time` |
| `requisition_open_date` | Date | The date the hiring request was formally approved | `YYYY-MM-DD` (some messy — see DQ section) |
| `requisition_close_date` | Date | The date hiring was completed or cancelled. NULL if still open | `YYYY-MM-DD` or NULL |
| `hiring_manager_id` | String | The person who will manage the new hire | Format: `HM-001` to `HM-030` |
| `recruiter_id` | String | The recruiter responsible for filling this role | Format: `REC-001` to `REC-008` |
| `headcount_approved` | Integer | How many people were approved to hire into this role | `1` or `2` |
| `status` | String | Current state of the requisition | `open`, `filled`, `cancelled`, `on_hold` |
| `target_fill_date` | Date | The date the hiring manager wanted the role filled by | `YYYY-MM-DD` |
| `job_level` | String | Seniority level of the role | `ic1` (junior), `ic2` (mid), `ic3` (senior), `manager`, `senior_manager`, `director`, `vp` |

**Department valid values (TalentFlow uses these exact names):**
- `Technology`
- `Product`
- `Data and Analytics`
- `Commercial`
- `Finance`
- `Operations`
- `People`
- `Legal and Compliance`

---

#### Table 2: `talentflow_candidates`
One row per candidate (a person who has applied). Note: one candidate can apply to multiple jobs, so one person can appear once here but have multiple rows in the applications table.

| Field | Data Type | Description | Valid Values / Format |
|---|---|---|---|
| `candidate_id` | String | Unique identifier for the candidate | Format: `CAND-0001` to `CAND-4200` |
| `first_name` | String | Candidate's first name | Free text. Mix of Lithuanian, Polish, Ukrainian, British, German names |
| `last_name` | String | Candidate's last name | Free text |
| `email` | String | Candidate's email address | Standard email format |
| `phone` | String | Candidate's phone number | International format where present, NULL where missing |
| `location_city` | String | City the candidate lives in | Free text |
| `location_country` | String | Country the candidate lives in | Full country name (e.g. "Lithuania", "Germany") |
| `current_company` | String | Where the candidate currently works | Free text, NULL if unemployed |
| `current_title` | String | The candidate's current job title | Free text |
| `linkedin_url` | String | Link to their LinkedIn profile | URL format or NULL |
| `created_date` | Date | When this candidate record was first created in TalentFlow | `YYYY-MM-DD` |

**Important note on duplicates:** Approximately 3% of candidates applied to more than one role. They will have separate `candidate_id` values but the same `email`. Some will have slightly different name spellings. The cleaning pipeline must identify and flag these.

---

#### Table 3: `talentflow_applications`
One row per application. This is the central table — it links a candidate to a job and tracks where they currently are in the process.

| Field | Data Type | Description | Valid Values / Format |
|---|---|---|---|
| `application_id` | String | Unique identifier for this application | Format: `APP-00001` to `APP-04200` |
| `candidate_id` | String | Links to `talentflow_candidates` | Foreign key |
| `job_id` | String | Links to `talentflow_jobs` | Foreign key |
| `source` | String | How the candidate found or was found for this role | See Source List below. **Messy — 20% have inconsistent values** |
| `source_subtype` | String | More detail on the source | E.g. "LinkedIn Recruiter" vs "LinkedIn Easy Apply" |
| `application_date` | Date | When the candidate submitted their application | `YYYY-MM-DD`. **8% have wrong format** |
| `current_stage` | String | The last pipeline stage this application reached | See Canonical Stage List in Part 2 |
| `current_stage_date` | Date | When the application entered its current stage | `YYYY-MM-DD` |
| `hired` | Boolean | Did this candidate get hired into this role? | `True` or `False` |
| `rejected` | Boolean | Was this candidate rejected? | `True` or `False` |
| `withdrawn` | Boolean | Did the candidate withdraw themselves? | `True` or `False` |

**Source valid values (canonical — what messy data will be standardised to):**
- `LinkedIn Organic` — candidate applied to a job posting without being contacted first
- `LinkedIn Paid` — candidate came via a sponsored job posting
- `LinkedIn Recruiter` — recruiter proactively reached out via LinkedIn Recruiter tool
- `Employee Referral` — referred by a current employee
- `Direct Application` — applied via the company careers page directly
- `Indeed` — applied via Indeed job board
- `Glassdoor` — applied via Glassdoor job board
- `Recruitment Agency` — sourced or submitted by a third-party agency
- `GitHub Sourcing` — recruiter found candidate via their GitHub profile
- `University Partnership` — came via a university careers event or partnership
- `Other` — any source that does not fit the above

---

#### Table 4: `talentflow_pipeline_events`
One row per stage transition. Every time a candidate moves forward, gets rejected, or withdraws, a new row is created here. This table is used to calculate how long candidates spend in each stage and where they drop out.

| Field | Data Type | Description | Valid Values / Format |
|---|---|---|---|
| `event_id` | String | Unique identifier for this event | Format: `EVT-00001` onwards |
| `application_id` | String | Links to `talentflow_applications` | Foreign key |
| `from_stage` | String | The stage the candidate was in before this event | See Canonical Stage List. **15% have inconsistent naming** |
| `to_stage` | String | The stage the candidate moved to | See Canonical Stage List. **15% have inconsistent naming** |
| `event_date` | Date | When this transition happened | `YYYY-MM-DD`. **2% have impossible sequences** |
| `event_type` | String | What kind of event this was | `advanced`, `rejected`, `withdrawn` |
| `rejection_reason` | String | Why the candidate was rejected (if applicable) | See Rejection Reason List. **NULL for 35% of rejections** |
| `interviewer_id` | String | The person who conducted the interview at this stage (if applicable) | Format: `INT-001` onwards, or NULL |
| `notes` | String | Free text notes entered by the recruiter | Free text or NULL |

---

#### Table 5: `talentflow_offers`
One row per offer. Created when a formal offer is extended to a candidate.

| Field | Data Type | Description | Valid Values / Format |
|---|---|---|---|
| `offer_id` | String | Unique identifier for this offer | Format: `OFR-001` onwards |
| `application_id` | String | Links to `talentflow_applications` | Foreign key |
| `offer_date` | Date | When the offer was formally extended | `YYYY-MM-DD` |
| `offer_amount` | Mixed | The salary offered. **12% are text strings not numbers** | Should be numeric (e.g. `45000`). Messy: `"€45,000"`, `"45k"`, `"45.000"` |
| `offer_currency` | String | Currency of the offer | `EUR`, `GBP`, `USD`, `PLN` |
| `equity_offered` | Boolean | Was equity (company shares) offered? | `True` or `False` |
| `offer_status` | String | What happened with the offer | `extended`, `accepted`, `declined`, `rescinded`, `expired` |
| `decline_reason` | String | Why the candidate declined (if applicable) | See Decline Reason List below, or NULL |
| `accepted_date` | Date | When the candidate formally accepted | `YYYY-MM-DD` or NULL |

**Decline reason valid values:**
- `compensation` — offer salary was too low
- `competing_offer` — candidate accepted a different company's offer
- `location` — candidate did not want to relocate or work from that location
- `role_fit` — candidate decided the role was not right for them
- `personal_reasons` — unspecified personal circumstances
- `no_response` — offer expired with no response from candidate

---

### SYSTEM 2: PeopleCore (HRIS — Human Resources Information System)
> PeopleCore is the fictional name for the system that manages employee records after someone is hired.
> It is modelled on Workday, a real HRIS used widely in enterprise companies.
> It stores payroll, performance, contracts, and terminations.

---

#### Table 6: `peoplecore_employees`
One row per employee (current and former). This is the master employee record.

| Field | Data Type | Description | Valid Values / Format |
|---|---|---|---|
| `employee_id` | String | Unique identifier for this employee | Format: `EMP-0001` to `EMP-0345` (300 active + 45 terminated) |
| `first_name` | String | Employee first name | Free text |
| `last_name` | String | Employee last name | Free text |
| `email` | String | Work email address | `firstname.lastname@enovatech.com` format |
| `department` | String | Which department the employee belongs to. **Does not match TalentFlow naming** | See Department Mapping below |
| `sub_department` | String | More specific team within department | E.g. "Backend", "Mobile", "DevOps" — NULL for smaller depts |
| `job_title` | String | Employee's current job title | Free text |
| `job_level` | String | Seniority level | `ic1`, `ic2`, `ic3`, `manager`, `senior_manager`, `director`, `vp` |
| `employment_type` | String | Type of contract | `full_time`, `part_time`, `contractor` |
| `hire_date` | Date | The date the employee formally accepted their offer. Used as the start of employment for HR purposes | `YYYY-MM-DD` |
| `start_date` | Date | The employee's first actual working day. Always on or after hire_date | `YYYY-MM-DD` |
| `manager_id` | String | The employee_id of this person's manager | Links back to this same table |
| `location_city` | String | City where the employee is based. **10% are inconsistent** | City name, "Remote", or NULL |
| `location_country` | String | Country where the employee is based | Full country name or NULL |
| `salary_amount` | Float | The employee's salary. **15% are monthly figures entered as if annual** | Should always be annual. E.g. `55000.00` |
| `salary_currency` | String | Currency of salary | `EUR`, `GBP`, `PLN`, `USD` |
| `salary_type` | String | Whether salary_amount is annual or monthly. **This field is the clue for fixing the salary issue** | `annual` or `monthly` |
| `gender` | String | Employee's gender | `m`, `f`, `non_binary`, `prefer_not_to_say` |
| `nationality` | String | Employee's nationality | Full country name |
| `status` | String | Current employment status | `active`, `terminated`, `on_leave`, `on_notice` |
| `termination_date` | Date | When employment ended. NULL if still employed | `YYYY-MM-DD` or NULL |
| `termination_reason` | String | Why the person left. **NULL for 30% of terminated employees** | `voluntary_resignation`, `involuntary_performance`, `involuntary_restructuring`, `end_of_contract`, `retirement`, or NULL |
| `ats_candidate_id` | String | The candidate_id from TalentFlow for this person. **NULL for 40% of employees** | Format: `CAND-0001` or NULL |

**Critical department name mismatch — TalentFlow vs PeopleCore:**

| TalentFlow Name | PeopleCore Name | Finance Plan Name |
|---|---|---|
| Technology | Engineering | Engineering & Product |
| Product | Product | Engineering & Product |
| Data and Analytics | Analytics | Analytics |
| Commercial | Growth | Sales & Marketing |
| Finance | Finance | Finance |
| Operations | Operations | Operations |
| People | HR | HR & Legal |
| Legal and Compliance | Legal | HR & Legal |

> This mapping table is one of the most important outputs of the cleaning pipeline.
> Every cross-system metric depends on it being correct.

---

#### Table 7: `peoplecore_performance`
One row per performance review. Not every employee has been reviewed — the company is young and the process is still being established.

| Field | Data Type | Description | Valid Values / Format |
|---|---|---|---|
| `review_id` | String | Unique identifier for this review | Format: `REV-0001` onwards |
| `employee_id` | String | Links to `peoplecore_employees` | Foreign key |
| `review_period` | String | Which review cycle this covers | Format: `Q1_2024`, `Q2_2024`, `H1_2024`, `H2_2024`, `Q1_2025`, `H1_2025` |
| `rating` | Integer | Performance score given by reviewer | `1` (significantly below expectations) to `5` (exceptional) |
| `reviewer_id` | String | The employee_id of the person who wrote the review | Links to `peoplecore_employees` |
| `submitted_date` | Date | When the review was submitted | `YYYY-MM-DD` |

**Rating scale definition (important for interpreting quality-of-hire metrics):**
- `1` — Significantly below expectations. Performance improvement plan likely.
- `2` — Below expectations. Development needed.
- `3` — Meets expectations. Solid, reliable performance.
- `4` — Exceeds expectations. Strong performer.
- `5` — Exceptional. Top performer, promotion candidate.

---

#### Table 8: `peoplecore_compensation`
One row per compensation change event. Captures every time someone's salary changed and why.

| Field | Data Type | Description | Valid Values / Format |
|---|---|---|---|
| `change_id` | String | Unique identifier for this change | Format: `CHG-0001` onwards |
| `employee_id` | String | Links to `peoplecore_employees` | Foreign key |
| `change_date` | Date | When the salary change took effect | `YYYY-MM-DD` |
| `old_salary` | Float | Salary before the change | Annual amount |
| `new_salary` | Float | Salary after the change | Annual amount |
| `change_reason` | String | Why the salary changed | `promotion`, `merit_increase`, `market_adjustment`, `role_change` |

---

### SYSTEM 3: Finance Headcount Plan
> This is a simple spreadsheet exported from the Finance team's planning tool.
> It shows how many people each department is approved to have in each quarter.
> It does not use the same department names as either TalentFlow or PeopleCore.

---

#### Table 9: `finance_headcount_plan`
One row per department per quarter.

| Field | Data Type | Description | Valid Values / Format |
|---|---|---|---|
| `plan_id` | String | Unique identifier for this row | Format: `PLAN-001` onwards |
| `department` | String | Department name in Finance taxonomy. **Does not match TalentFlow or PeopleCore** | See mapping table above |
| `quarter` | String | Which quarter this plan covers | Format: `Q3_2023`, `Q4_2023`, `Q1_2024`, `Q2_2024`, `Q3_2024`, `Q4_2024`, `Q1_2025`, `Q2_2025` |
| `headcount_approved` | Integer | How many employees are approved to be in this department at end of quarter | Whole number |
| `headcount_actual` | Integer | How many employees were actually in the department at end of quarter. NULL for future quarters | Whole number or NULL |
| `notes` | String | Any notes from the Finance team | Free text or NULL. Key note: "Emergency headcount approvals not reflected in this plan" |

**Known plan data issues:**
- Q4 data is missing for Legal and Operations (those department heads had not submitted)
- Engineering Q2 approved headcount is 85 but actual was 92 due to emergency approvals outside the standard plan process

---

## PART 2: CANONICAL RECRUITMENT FUNNEL STAGE LIST

A canonical list means: these are the official, standardised names we will use for every pipeline stage throughout the entire project. Any variation found in the raw data will be mapped to one of these names.

### The 11 Canonical Stages (in order)

| Stage Number | Canonical Name | What Happens Here | Typical Duration | Who Is Responsible |
|---|---|---|---|---|
| 0 | `Applied` | Candidate submits their application | Instant event | Candidate |
| 1 | `Resume Screen` | Recruiter reviews the CV and decides whether to advance | 1–5 business days | Recruiter |
| 2 | `Recruiter Screen` | 20–30 min call to check basics: motivation, availability, salary, work authorisation | 3–7 days to schedule | Recruiter |
| 3 | `Hiring Manager Screen` | 30–45 min call with the manager who will make the hire decision | 3–7 days to schedule | Hiring Manager |
| 4 | `Technical Assessment` | Take-home task or coding challenge sent to candidate. Only for technical and analytical roles | 5–14 days (candidate completes, then reviewer scores) | Candidate + Assessor |
| 5 | `Technical Interview` | Live interview to go deeper on technical skills. Used for senior or specialist roles | 3–7 days to schedule | Interviewer panel |
| 6 | `Final Panel Interview` | Multi-person interview with team and/or senior stakeholders | 3–7 days to schedule | Interview panel |
| 7 | `Reference Check` | 2–3 references contacted before offer is made | 3–5 days | Recruiter |
| 8 | `Offer` | Verbal offer extended to candidate | Instant to 2 days | Recruiter / HR |
| 9 | `Offer Accepted` | Candidate formally accepts the written offer | 1–3 days | Candidate |
| 10 | `Hired` | Candidate's start date confirmed. Record created in HRIS | Day of start | HR / People Ops |

**Terminal stages (application ends here, no further movement):**

| Stage Name | Meaning |
|---|---|
| `Rejected — Resume Screen` | Rejected during or after CV review |
| `Rejected — Recruiter Screen` | Rejected after recruiter call |
| `Rejected — Hiring Manager Screen` | Rejected after hiring manager call |
| `Rejected — Technical Assessment` | Rejected based on assessment submission |
| `Rejected — Technical Interview` | Rejected after live technical interview |
| `Rejected — Final Panel` | Rejected after panel interview |
| `Rejected — Reference Check` | Offer rescinded based on reference check |
| `Offer Declined` | Candidate turned down the offer |
| `Withdrawn` | Candidate withdrew themselves at any stage |
| `Role Cancelled` | Role was cancelled before being filled |

### Stage Mapping: Messy → Canonical
This is the full list of messy variants found in the raw data and the canonical name each maps to.

| Raw Value Found in Data | Maps To |
|---|---|
| `Phone Screen` | `Recruiter Screen` |
| `phone_screen` | `Recruiter Screen` |
| `Phone Interview` | `Recruiter Screen` |
| `PHONE SCREEN` | `Recruiter Screen` |
| `Recruiter Call` | `Recruiter Screen` |
| `Recruiter Screen` | `Recruiter Screen` *(already correct)* |
| `phone screen` | `Recruiter Screen` |
| `recruiter_screen` | `Recruiter Screen` |
| `HM Screen` | `Hiring Manager Screen` |
| `HM Call` | `Hiring Manager Screen` |
| `Hiring Manager Screen` | `Hiring Manager Screen` *(already correct)* |
| `hiring_manager_screen` | `Hiring Manager Screen` |
| `Manager Screen` | `Hiring Manager Screen` |
| `Tech Assessment` | `Technical Assessment` |
| `technical_assessment` | `Technical Assessment` |
| `Take Home Task` | `Technical Assessment` |
| `Coding Challenge` | `Technical Assessment` |
| `Technical Assessment` | `Technical Assessment` *(already correct)* |
| `Tech Interview` | `Technical Interview` |
| `technical_interview` | `Technical Interview` |
| `Live Coding` | `Technical Interview` |
| `Technical Interview` | `Technical Interview` *(already correct)* |
| `Panel` | `Final Panel Interview` |
| `Final Panel` | `Final Panel Interview` |
| `Final Interview` | `Final Panel Interview` |
| `final_panel_interview` | `Final Panel Interview` |
| `Final Panel Interview` | `Final Panel Interview` *(already correct)* |
| `Refs` | `Reference Check` |
| `Reference Check` | `Reference Check` *(already correct)* |
| `reference_check` | `Reference Check` |
| `References` | `Reference Check` |
| `CV Review` | `Resume Screen` |
| `Resume Review` | `Resume Screen` |
| `CV Screen` | `Resume Screen` |
| `resume_screen` | `Resume Screen` |
| `Resume Screen` | `Resume Screen` *(already correct)* |

### Which Stages Apply to Which Role Types

Not every role goes through every stage. This table defines which stages are expected for each role category.

| Stage | IC Roles (Junior/Mid) | IC Roles (Senior) | Manager / Senior Manager | Director / VP |
|---|---|---|---|---|
| Applied | ✓ | ✓ | ✓ | ✓ |
| Resume Screen | ✓ | ✓ | ✓ | ✓ |
| Recruiter Screen | ✓ | ✓ | ✓ | ✓ |
| Hiring Manager Screen | ✓ | ✓ | ✓ | ✓ |
| Technical Assessment | ✓ (tech/analytical only) | ✓ (tech/analytical only) | Sometimes | Rarely |
| Technical Interview | — | ✓ (tech/analytical only) | — | — |
| Final Panel Interview | ✓ | ✓ | ✓ | ✓ |
| Reference Check | — | ✓ | ✓ | ✓ |
| Offer | ✓ | ✓ | ✓ | ✓ |
| Offer Accepted | ✓ | ✓ | ✓ | ✓ |
| Hired | ✓ | ✓ | ✓ | ✓ |

---

## PART 3: DATA QUALITY ISSUE LOG

This log documents every known data quality issue before cleaning begins. For each issue it records: what the problem is, how widespread it is, what the cleaning rule is, and what cannot be fixed and must be flagged instead.

This log becomes the basis for the Data Quality Report (Deliverable 1).

---

### ISSUE LOG — TalentFlow (ATS)

---

**DQ-ATS-01: Inconsistent stage naming**

| Attribute | Detail |
|---|---|
| Affected table | `talentflow_pipeline_events` |
| Affected field | `from_stage`, `to_stage` |
| Prevalence | ~15% of pipeline event records |
| Description | The same recruitment stage was entered under different names by different recruiters over time. Some used spaces, some used underscores, some used abbreviations, some used all caps. |
| Example | `"Phone Screen"`, `"phone_screen"`, `"PHONE SCREEN"`, `"Recruiter Call"` all mean `"Recruiter Screen"` |
| Cleaning rule | Apply the Stage Mapping table from Part 2. Standardise all values to canonical names. Case-insensitive matching with strip whitespace first. |
| Unresolvable? | No — all variants have been mapped in Part 2. Any value not in the map gets flagged as `UNMAPPED_STAGE` for manual review. |
| Impact if uncleaned | Stage duration calculations will be wrong. Funnel conversion rates will be split across multiple fake stages. |

---

**DQ-ATS-02: Mixed date formats**

| Attribute | Detail |
|---|---|
| Affected tables | `talentflow_applications`, `talentflow_pipeline_events`, `talentflow_offers` |
| Affected fields | All date fields |
| Prevalence | ~8% of date fields |
| Description | Most dates are `YYYY-MM-DD` (ISO standard). A subset are `DD/MM/YYYY` (European format). A smaller subset are `MM/DD/YYYY` (US format). Some cases are genuinely ambiguous — e.g. `05/04/2024` could be 5 April or 4 May. |
| Example | `2024-03-15` (correct), `15/03/2024` (European — unambiguous), `03/15/2024` (US — unambiguous), `05/04/2024` (ambiguous) |
| Cleaning rule | Step 1: try ISO parse. Step 2: if day > 12, it must be `DD/MM/YYYY` (day cannot be > 12 in US format). Step 3: if month > 12, it must be `MM/DD/YYYY`. Step 4: if ambiguous (both day and month ≤ 12), resolve using surrounding dates for the same application (earlier stages must predate later stages). Step 5: if still unresolvable, flag as `DATE_AMBIGUOUS`. |
| Unresolvable? | A small number of ambiguous dates cannot be resolved from context. These are flagged as `DATE_AMBIGUOUS` and excluded from time-based calculations. |
| Impact if uncleaned | Time-to-hire and time-to-fill calculations will be wrong for affected records. Some duration values will appear negative. |

---

**DQ-ATS-03: Offer amounts as text strings**

| Attribute | Detail |
|---|---|
| Affected table | `talentflow_offers` |
| Affected field | `offer_amount` |
| Prevalence | ~12% of offer records |
| Description | The offer_amount field should contain a plain number (e.g. `45000`). A subset were entered as formatted text strings by recruiters copy-pasting from emails or documents. |
| Example | `"€45,000"` → `45000`, `"45k"` → `45000`, `"45.000"` (European decimal format) → `45000` |
| Cleaning rule | Strip currency symbols (`€`, `£`, `$`). Strip commas. Convert `k` suffix by multiplying by 1000. Handle European decimal format (period as thousands separator) by checking: if a period appears and there are exactly 3 digits after it and no comma, treat the period as a thousands separator not a decimal point (e.g. `45.000` → `45000`, but `45000.50` → `45000.50`). Convert result to float. |
| Unresolvable? | Values that cannot be parsed after all rules are applied get flagged as `AMOUNT_PARSE_ERROR`. |
| Impact if uncleaned | Salary analysis and cost-per-hire calculations will include string values and cause errors or silently produce wrong results. |

---

**DQ-ATS-04: Duplicate candidate records**

| Attribute | Detail |
|---|---|
| Affected table | `talentflow_candidates` |
| Affected field | `email`, `first_name`, `last_name` |
| Prevalence | ~3% of candidate records |
| Description | The same person applied to two different roles. TalentFlow created two separate candidate_id records. Some have identical names; some have slightly different spellings (data entry error or nickname). |
| Example | `CAND-0412`: "Jon Smith", `jon.smith@gmail.com` and `CAND-1847`: "John Smith", `jon.smith@gmail.com` — same person |
| Cleaning rule | Step 1: find all records with the same email address. Step 2: for those with different names, compute fuzzy string similarity on first_name + last_name (using fuzzywuzzy). A score ≥ 85 is treated as a likely duplicate. Step 3: flag as `PROBABLE_DUPLICATE` with the matching candidate_id. Do not merge automatically — document for manual review. |
| Unresolvable? | Deduplication is flagged, not auto-resolved. The analyst must review flagged pairs before merging to avoid incorrectly collapsing two different people with the same email (unlikely but possible). |
| Impact if uncleaned | Application counts will be inflated. Some candidates will appear to have applied to multiple roles when they have (which is valid) but with the same application counted twice. |

---

**DQ-ATS-05: Source field inconsistencies**

| Attribute | Detail |
|---|---|
| Affected table | `talentflow_applications` |
| Affected field | `source` |
| Prevalence | ~20% of records |
| Description | The source field was free text. Different recruiters entered the same source differently. LinkedIn alone appears in at least 7 different formats. |
| Example | `"LinkedIn"`, `"linkedin"`, `"Linked In"`, `"LI"`, `"LinkedIn Recruiter"`, `"LinkedIn Jobs"`, `"linkedin.com"` |
| Cleaning rule | Lowercase, strip whitespace, then apply source mapping table. All LinkedIn variants map to `LinkedIn Organic`, `LinkedIn Paid`, or `LinkedIn Recruiter` based on subtype where available, defaulting to `LinkedIn Organic` if subtype is missing. See full source canonical list in Part 1 (Table 3). |
| Unresolvable? | Sources that do not match any pattern after normalisation are mapped to `Other` and flagged for review. |
| Impact if uncleaned | Source effectiveness analysis will be fragmented. LinkedIn will appear to have a fraction of its actual volume split across 7 pseudo-sources. |

---

**DQ-ATS-06: Impossible date sequences**

| Attribute | Detail |
|---|---|
| Affected table | `talentflow_pipeline_events` |
| Affected field | `event_date` (cross-record) |
| Prevalence | ~2% of applications |
| Description | Data entry errors mean some stage transition dates are logically impossible. A candidate cannot be screened before they applied. A technical interview cannot happen before a recruiter screen. |
| Example | Application date: `2024-06-15`. Resume Screen event date: `2024-06-10` (5 days before application — impossible). |
| Cleaning rule | For each application, sort all events chronologically. Flag any event whose date is: (a) before the application date, or (b) before the date of any preceding stage. Flag as `DATE_SEQUENCE_ERROR`. Do not attempt to correct — the original source cannot be verified. |
| Unresolvable? | Yes — these records are flagged and excluded from time-to-hire calculations. They are retained in the data but excluded from metric views with a documented filter. |
| Impact if uncleaned | Negative duration values in pipeline velocity calculations. Time-to-hire averages will be pulled down or crash Python/SQL calculations. |

---

**DQ-ATS-07: Unclosed requisitions**

| Attribute | Detail |
|---|---|
| Affected table | `talentflow_jobs` |
| Affected field | `status`, `requisition_close_date` |
| Prevalence | ~10% of jobs |
| Description | Some roles were filled (a hire exists in HRIS) but the recruiter never updated the job status in TalentFlow. The role still shows as `open` with a NULL close date. |
| Cleaning rule | Join TalentFlow jobs to HRIS employees on candidate ID or name+date. If a hire is confirmed in HRIS and the job is still marked `open`, flag as `STATUS_MISMATCH`. Update `status` to `filled` and derive `requisition_close_date` from the hire's `start_date`. Log the change. |
| Unresolvable? | If no match can be confirmed in HRIS, leave as `open` and note it. |
| Impact if uncleaned | Open role counts will be overstated. Headcount vs plan analysis will be wrong. |

---

**DQ-ATS-08: Missing rejection reasons**

| Attribute | Detail |
|---|---|
| Affected table | `talentflow_pipeline_events` |
| Affected field | `rejection_reason` |
| Prevalence | ~35% of rejected applications have NULL rejection reason |
| Description | Recruiters advanced candidates without recording why others were rejected. The field was not mandatory in TalentFlow. |
| Cleaning rule | No fix possible. Flag NULL rejection reasons as `REASON_NOT_RECORDED`. Do not infer or impute. |
| Unresolvable? | Yes — this is a process failure, not a data error. The CHRO recommendations brief will recommend making rejection reason mandatory. |
| Impact if uncleaned | Dropout analysis by reason is not possible for 35% of records. Any percentage figures derived from rejection reasons must be presented as "of rejections where reason was recorded" not "of all rejections." |

---

**DQ-ATS-09: Stage skipping**

| Attribute | Detail |
|---|---|
| Affected table | `talentflow_pipeline_events` |
| Affected field | `from_stage`, `to_stage` |
| Prevalence | ~8% of applications |
| Description | Some applications jump from `Applied` directly to `Final Panel Interview` or `Offer` with no intermediate stages recorded. This is not impossible (internal candidates, referrals with waived stages) but is usually a logging failure. |
| Cleaning rule | Identify stage skips by checking whether the `from_stage` → `to_stage` transition skips more than one level in the canonical order. Flag applications with any skip as `STAGE_SKIP_DETECTED`. Note: do not remove these records. Mark with a flag column `has_stage_skip = True`. Exclude from pipeline velocity calculations (since intermediate durations cannot be computed). Include in funnel conversion counts. |
| Unresolvable? | Cannot determine which stages were actually completed. Only flag and exclude from velocity metrics. |
| Impact if uncleaned | Pipeline velocity will be artificially shortened for affected applications. Average time-in-stage calculations will be understated. |

---

### ISSUE LOG — PeopleCore (HRIS)

---

**DQ-HRIS-01: Salary type inconsistency**

| Attribute | Detail |
|---|---|
| Affected table | `peoplecore_employees` |
| Affected field | `salary_amount`, `salary_type` |
| Prevalence | ~15% of employees |
| Description | Most salary amounts are annual. But some were entered as monthly amounts (the way employees often think about salary in Lithuania, Poland, and other Central/Eastern European countries). The `salary_type` field should record whether it is `annual` or `monthly` but it is not always populated correctly. |
| Example | A Lithuanian engineer earning €3,500/month was entered as `salary_amount = 3500`, `salary_type = annual`. The correct annual salary is `3500 × 12 = 42000`. |
| Cleaning rule | Step 1: Where `salary_type = 'monthly'`, multiply `salary_amount` by 12 and update `salary_type` to `annual`. Step 2: For records where `salary_type` says `annual` but the amount looks implausibly low (e.g. below €15,000 annual for any full-time role), cross-reference against expected salary ranges by country and job level. If multiplying by 12 gives a plausible salary, flag as `PROBABLE_MONTHLY_ENTRY` and multiply by 12. Step 3: Log all changes. |
| Unresolvable? | Records where the salary is ambiguous even after cross-referencing are flagged as `SALARY_REVIEW_NEEDED`. |
| Impact if uncleaned | Average salary calculations, cost-per-hire analysis, and compensation equity analysis will be badly wrong. Some salaries will appear as 1/12 of their actual value. |

---

**DQ-HRIS-02: Department name mismatch with ATS**

| Attribute | Detail |
|---|---|
| Affected tables | `peoplecore_employees` vs `talentflow_jobs` |
| Affected field | `department` |
| Prevalence | 100% of employees — this is a systematic mismatch, not random errors |
| Description | TalentFlow and PeopleCore were implemented separately and use different department taxonomy. No one ever created a mapping between them. |
| Cleaning rule | Apply the Department Mapping table from Part 1 consistently. Create a `department_canonical` field on all tables that uses a single agreed taxonomy. The canonical names will be the TalentFlow names (Technology, Product, Data and Analytics, Commercial, Finance, Operations, People, Legal and Compliance) since those are more specific. |
| Unresolvable? | No — the mapping is complete and documented in Part 1. |
| Impact if uncleaned | Any cross-system analysis (e.g. time-to-hire by department comparing ATS to HRIS) will produce wrong results or null matches. |

---

**DQ-HRIS-03: ATS-to-HRIS join failure**

| Attribute | Detail |
|---|---|
| Affected tables | `peoplecore_employees`, `talentflow_candidates` |
| Affected field | `ats_candidate_id` in HRIS |
| Prevalence | ~40% of employees have NULL `ats_candidate_id` |
| Description | The `ats_candidate_id` field in PeopleCore was supposed to be filled in during the onboarding process to link each employee back to their application record. It was not done consistently. For 40% of employees, this field is NULL and the join cannot be made directly. |
| Cleaning rule | For records with NULL `ats_candidate_id`, attempt a fuzzy join: match on `first_name` + `last_name` + hire_date within 7 days of ATS offer_accepted_date. A match on all three is treated as a confirmed link. A match on name only (without date confirmation) is flagged as `PROBABLE_MATCH` and excluded from quality-of-hire metrics until confirmed. |
| Unresolvable? | Some employees will have no ATS match at all (pre-ATS employees — see DQ-HRIS-04). These are expected. |
| Impact if uncleaned | Quality-of-hire analysis (linking performance ratings back to recruiter, source, and hiring manager) is impossible without this join. It is the most analytically important link in the entire project. |

---

**DQ-HRIS-04: Pre-ATS employees**

| Attribute | Detail |
|---|---|
| Affected table | `peoplecore_employees` |
| Affected field | `ats_candidate_id`, `hire_date` |
| Prevalence | ~25% of current employees |
| Description | The company had ~75 employees before TalentFlow was implemented. These people exist in PeopleCore but have no ATS record. They were hired before the ATS existed, so no application, pipeline events, or offer data exists for them. |
| Cleaning rule | Identify by: `hire_date` before TalentFlow go-live date AND `ats_candidate_id` is NULL. Tag these records with `pre_ats = True`. Exclude from all ATS-dependent metrics (time-to-hire, source effectiveness, funnel conversion). Include in all HRIS-dependent metrics (headcount, attrition, performance). |
| Unresolvable? | Yes — by definition. Historical ATS data does not exist. This must be documented as a limitation. |
| Impact if uncleaned | Including pre-ATS employees in ATS metrics will suppress conversion rates, inflate headcount-to-applications ratios, and produce misleading time-to-hire figures. |

---

**DQ-HRIS-05: Missing termination reasons**

| Attribute | Detail |
|---|---|
| Affected table | `peoplecore_employees` |
| Affected field | `termination_reason` |
| Prevalence | ~30% of terminated employees |
| Description | The termination_reason field did not exist when the company first set up PeopleCore. Employees who left in the early period have NULL in this field. |
| Cleaning rule | Do not impute or guess. Replace NULL with the string `unknown`. Ensure attrition analysis always distinguishes between `voluntary`, `involuntary`, and `unknown` — never combine unknown with either category. |
| Unresolvable? | Yes — historical records cannot be recovered. |
| Impact if uncleaned | Treating NULL as voluntary or involuntary would produce misleading attrition analysis. The voluntary attrition rate would be overstated or understated depending on the assumption made. |

---

**DQ-HRIS-06: Inconsistent location data**

| Attribute | Detail |
|---|---|
| Affected table | `peoplecore_employees` |
| Affected fields | `location_city`, `location_country` |
| Prevalence | ~10% of employees |
| Description | Location data was entered inconsistently. Some records have city only, some have both city and country, some have country only. Remote workers sometimes have the value `"Remote"` as their city, which is not a city. |
| Cleaning rule | Step 1: Where city = `"Remote"`, move `"Remote"` to a new boolean field `is_remote = True` and set `location_city = NULL`. Step 2: Where city is present but country is missing, infer country from city using a lookup table for common cities in the dataset (Vilnius → Lithuania, Warsaw → Poland, Berlin → Germany, London → UK, Amsterdam → Netherlands, Tallinn → Estonia, Kyiv → Ukraine, Krakow → Poland, Riga → Latvia). Step 3: Where only country is present, leave `location_city = NULL` — do not guess city. |
| Unresolvable? | Records with neither city nor country after cleaning are flagged as `LOCATION_UNKNOWN`. |
| Impact if uncleaned | Geographic analysis of workforce composition will be unreliable. Remote worker headcount will be understated. |

---

### ISSUE LOG — Finance Headcount Plan

---

**DQ-PLAN-01: Department naming mismatch**

| Attribute | Detail |
|---|---|
| Affected table | `finance_headcount_plan` |
| Affected field | `department` |
| Prevalence | 100% — systematic |
| Description | Finance used its own department taxonomy that matches neither TalentFlow nor PeopleCore. Technology and Product are combined as "Engineering & Product." People and Legal are combined as "HR & Legal." Marketing is called "Sales & Marketing." |
| Cleaning rule | Apply department mapping table from Part 1. Split combined categories where needed. When splitting "Engineering & Product," use the proportional headcount from PeopleCore as at the plan date to allocate the approved headcount between the two departments. |
| Unresolvable? | The split of combined Finance categories is an approximation — flag this in the metric documentation. |
| Impact if uncleaned | Headcount vs plan analysis by department will be impossible. |

---

**DQ-PLAN-02: Missing Q4 data**

| Attribute | Detail |
|---|---|
| Affected table | `finance_headcount_plan` |
| Affected field | `headcount_approved` |
| Prevalence | 2 out of 8 departments for Q4 |
| Description | Legal and Operations department heads had not submitted their Q4 headcount plans at the time of the Finance export. These rows are missing entirely. |
| Cleaning rule | Do not impute. Insert placeholder rows with `headcount_approved = NULL` and a note field value of `"Q4 plan not submitted"`. Ensure forecasting model handles NULL plan values gracefully (show as "plan not available" not as zero). |
| Unresolvable? | Yes — until Finance collects the missing submissions. |
| Impact if uncleaned | Q4 forecast variance analysis will show 100% gap for Legal and Operations if NULL is treated as zero. |

---

**DQ-PLAN-03: Engineering headcount discrepancy**

| Attribute | Detail |
|---|---|
| Affected table | `finance_headcount_plan` |
| Affected field | `headcount_approved` vs `headcount_actual` |
| Prevalence | 1 specific cell (Engineering Q2) |
| Description | Engineering Q2 approved headcount is 85 but actual was 92 because 7 hires were approved via an emergency headcount process that bypassed the standard plan. These emergency approvals exist in HRIS but not in the Finance plan. |
| Cleaning rule | Do not change the approved figure (85). Instead, add a column `headcount_emergency_approved` to capture the 7 additional approved heads. Document this in the metric notes. The variance analysis must show: plan = 85, emergency = 7, total approved = 92, actual = 92, variance = 0 (not -7). |
| Unresolvable? | No — the data is correct as-is, it just needs proper context to be interpreted correctly. |
| Impact if uncleaned | A naive plan vs actual comparison would show Engineering Q2 as 8% over plan, which would be misleading and alarm the CHRO unnecessarily. |

---

## SUMMARY STATISTICS

| System | Issue Code | Issue Description | Records Affected | Resolvable? |
|---|---|---|---|---|
| TalentFlow | DQ-ATS-01 | Inconsistent stage naming | ~630 pipeline events | Yes |
| TalentFlow | DQ-ATS-02 | Mixed date formats | ~336 date fields | Mostly |
| TalentFlow | DQ-ATS-03 | Offer amounts as text | ~21 offer records | Yes |
| TalentFlow | DQ-ATS-04 | Duplicate candidates | ~126 candidate records | Flagged only |
| TalentFlow | DQ-ATS-05 | Source field inconsistencies | ~840 applications | Yes |
| TalentFlow | DQ-ATS-06 | Impossible date sequences | ~84 applications | No — flag and exclude |
| TalentFlow | DQ-ATS-07 | Unclosed requisitions | ~5 jobs | Mostly |
| TalentFlow | DQ-ATS-08 | Missing rejection reasons | ~35% of rejections | No — structural gap |
| TalentFlow | DQ-ATS-09 | Stage skipping | ~336 applications | No — flag and exclude |
| PeopleCore | DQ-HRIS-01 | Salary type inconsistency | ~52 employees | Yes |
| PeopleCore | DQ-HRIS-02 | Department name mismatch | All 345 employees | Yes — mapping table |
| PeopleCore | DQ-HRIS-03 | ATS-to-HRIS join failure | ~138 employees | Partly — fuzzy join |
| PeopleCore | DQ-HRIS-04 | Pre-ATS employees | ~86 employees | No — excluded from ATS metrics |
| PeopleCore | DQ-HRIS-05 | Missing termination reasons | ~14 terminated employees | No — flag as unknown |
| PeopleCore | DQ-HRIS-06 | Inconsistent location data | ~35 employees | Mostly |
| Finance Plan | DQ-PLAN-01 | Department naming mismatch | All 40 rows | Yes — mapping table |
| Finance Plan | DQ-PLAN-02 | Missing Q4 data | 2 departments | No — document as missing |
| Finance Plan | DQ-PLAN-03 | Engineering discrepancy | 1 cell | Yes — add emergency column |

---

*End of Step 1 Foundations Document*  
*Next step: Data generation script (Step 2)*  
*This document must be reviewed and confirmed before any code is written*

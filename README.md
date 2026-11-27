# Daily Attendance App

A mobile app that replaces the paper attendance register in a firm. Supervisors record each employee's daily attendance and in/out times, and the director sees every team's records and uses the monthly report for salaries.

- **Platform:** Android app, shared directly as an APK (no Play Store needed)
- **Tech stack:** Flutter (app) + Firebase (login and online database)
- **Users:** Director / top-level admins, supervisors and accountants (view only). Employees do not log in.


## Running it yourself

The Firebase config files (`android/app/google-services.json` and `lib/firebase_options.dart`) are not in this repo. To build the app, create your own Firebase project (Authentication with Phone sign-in, plus Firestore; see "Phone login setup" below), then run:

```
dart pub global activate flutterfire_cli
flutterfire configure
flutter run
```

---

## Roles

| Role | Can do |
|---|---|
| **Director (Super Admin)** | See and edit all teams' attendance, create teams, add supervisors, **add, edit and deactivate employees** (only the director can), change settings, export monthly reports. Logs in with their **mobile number + SMS code**. |
| **Supervisor (Team Admin)** | Put existing employees on or off their teams' monthly lists, and mark daily attendance, for **their own teams only**. Can't add new employees, change their details or deactivate them. One supervisor can handle **several teams**, and one team can have several supervisors. Logs in with their **mobile number + SMS code**, the number the director added them with. |
| **Accountant (View only)** | The link between the supervisors and the director. Sees what the director sees: the dashboard, every team's sheets, the teams, employee history and the monthly reports (and can share the Excel file). **Can't change anything**: there are no save, add, edit or delete buttons, and the security rules refuse any change. Added, edited and deactivated by the director by **mobile number**, like a supervisor; logs in with **mobile number + SMS code**. |
| **Employee** | No login. A record (Emp ID, name, designation) that supervisors mark attendance for. Which team someone works in is set **month by month**: each team has a monthly list of people (see below). Someone can be on more than one team's list. |

## Company structure

```
Company
 ├── Marketing  → Supervisor(s) → Employees
 ├── Finance    → Supervisor(s) → Employees
 └── Legal      → Supervisor(s) → Employees
```

---

## App flow

### 1. One-time setup (Director)
```
Install app → Log in with mobile number + SMS code
   → A number not in any company yet is offered "Set up a new company"
     (company name + your name) and becomes its director
   → Create teams (Marketing, Finance, Legal…)
   → Add supervisors (name + mobile number) and assign each one or more teams
   → Set office rules (office hours, late cutoff, half-day rule)
```

### 2. Supervisor setup
```
Install app → Log in with the mobile number the director added + the SMS code
   → Add employees to each of their teams (Emp ID, name, designation)
```

### 3. Daily attendance (supervisor)
```
Open app → Today's Attendance → pick a team from the selector
   For each employee:
      Status: Present / Absent / Half-day / Leave
      In time / Out time
   → Hours worked and the "Late" flag are calculated automatically
   → Save → data goes online instantly → switch to the next team
```
- The "All my teams" view shows which teams are done and which are pending today.
- Supervisors can edit the **last 7 days**. Only the director can change older records.
- There are no passwords or PINs to forget: each login on a new phone gets a fresh SMS code.
- A supervisor who changes their number is added again with the new number (and the old entry deactivated), then given their teams back.

### 4. Director dashboard
```
Dashboard
 ├── Today: present / absent / pending per team
 ├── Team view → that day's full log
 ├── Employee view → history for any date range
 └── Reports → export to Excel
```

### 5. Month-end payroll
```
Reports → pick a month (or any dates) → review → share the Excel file → process salaries
```
The report shows, per employee: days present, absent, half-days, leaves, late marks, hours and **Dihadi** (days' pay earned, see below). The app doesn't store pay rates: in the Excel file the director types each worker's daily rate once on the Summary tab, and the Amount, D\*A and pay totals fill in by themselves. The Excel file has a summary tab, an "All employees" sheet with each worker's block (one row per day, yellow total; a printed page each), and one tab per worker.

## Pay rule: Dihadi

Each day's hours earn a share of a day's pay, the **Dihadi**. Pay = total Dihadi × the worker's daily rate (typed by the director in the Excel file).

| Hours | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Dihadi | 0.125 | 0.25 | 0.5 | 0.5 | 0.625 | 0.75 | 0.875 | 1 | 1 | 1.25 | 1.25 | 1.5 | 1.625 | 1.75 | 1.75 | 2 |

- Hours are rounded to the nearest half hour (8 h 15 m → 8 h 30 m; 8 h 14 m → 8 h). A half hour adds 0.0625 (8 h 30 m and 9 h 30 m → 1.0625).
- Past 16 hours, each hour adds 0.125.
- Absent and leave earn 0. Late marks are shown but don't reduce pay.
- A day with an in or out time missing earns 0 and is flagged, so it can be fixed.
- The rule is in [day_value.dart](lib/core/models/day_value.dart).

---

## Default rules (the director can change these in Settings)

| Rule | Default |
|---|---|
| Office hours | 9:30 AM – 6:30 PM |
| Late after | 9:45 AM |
| Half-day (status shown on the sheet) | Less than 4 hours worked. Pay goes by the Dihadi table, not the status |
| Supervisor edit window | Last 7 days |

---

## Data structure (Firebase Firestore)

| Path | Stores |
|---|---|
| **users/{phone}** | Director/supervisors/accountants: company ID, role (`director`, `supervisor` or `accountant`), name, phone, list of team IDs, active. Keyed by the mobile number in international form (`+919876543210`), which is also what the login token carries, so the app finds the company right after login and a director can add a supervisor before they ever log in. One number belongs to one company |
| **companies/{companyId}** | Name, creator's number, office rules (`settings`) |
| **companies/{companyId}/teams** | Team name. Who supervises a team is stored on each supervisor (`teamIds` in **users**), so the two can't disagree |
| **companies/{companyId}/employees** | Keyed by Emp ID (so IDs are unique in the company): Emp ID, name, designation (optional), active/inactive. Every supervisor can read the staff list and keep the details up to date |
| **companies/{companyId}/rosters** | Each team's monthly list of people, keyed `{teamId}_{yyyy-MM}`: team, month, Emp IDs. A month with no list of its own uses the latest earlier month's, so a new month automatically starts with last month's people. Supervisors change their own teams' lists for this month or next; older ones only the director |
| **companies/{companyId}/attendance** | One sheet per team per day, keyed `{teamId}_{yyyy-MM-dd}`: team, date, an entry per employee (status, in/out time, minutes worked, late flag; `guest` for someone lent from another team for the day; `workingIn` for someone absent because they worked in another team), who saved it last and when. One document per sheet, so a team's day is saved in one go. Every member can read all sheets (to see who was lent where); supervisors save their own teams' sheets within the edit window. The monthly report adds an employee's teams together |

**Phone login setup** (Firebase console, once per project):
1. Authentication → Sign-in method → turn on **Phone**.
2. Project settings → your Android app → add the **SHA-1 and SHA-256** fingerprints of both the debug key and the release key (`keytool -list -v -keystore <keystore>`, or `./gradlew signingReport` in `android/`). Without them Android can't send codes.
3. For testing without real SMS: Authentication → Sign-in method → Phone → **Phone numbers for testing** (e.g. `+91 90000 00001`, code `123456`). Real SMS beyond the free daily allowance needs the Blaze (pay-as-you-go) plan; the console says so when it's needed.

**Security rules:** supervisors can change only the teams on their list (they can read the whole company's staff lists and sheets, to see who works where). The director can read and write everything. An accountant can read everything in their company and write nothing. Nobody can access anything without logging in.
The rules live in [firestore.rules](firestore.rules). To test and publish them (Java is needed; Android Studio's copy works: `D:\Android studio\Android studio\jbr`):
```
cd firestore_tests
npm install        # first time only
npm test           # runs the rules tests on a local emulator
cd ..
firebase deploy --only firestore:rules --project daily-attendance-b1b1e
```

### Built for many firms
The app starts with one firm but is meant to be offered to other firms later. So, from the first version:
- The app is branded **"Daily Attendance"**, not with any one firm's name. Each firm's name is stored in its `companies` record and shown after login.
- Every user, team, employee and attendance record belongs to exactly one company. A firm's teams, employees and attendance are stored under its own `companies/{companyId}` record.
- Security rules keep firms completely separate: a director's "everything" means everything **in their own company**.
- Each new firm's director logs in with their number and sets up their own company.

## Screens

1. **Login**
2. **Director:** Dashboard · Teams · Employees · People (supervisors and accountants) · Reports · Settings
3. **Supervisor:** Today's Attendance · My Employees · Past Days
4. **Accountant (view only):** Dashboard (with employee history) · Teams · Reports (with the Excel file)

---

## Build phases

Each phase is finished and tested on a real phone before moving to the next.

### Phase 0: Prepare the tools
- [x] Install **Android Studio** and put the Android SDK on the **D: drive** (`D:\Android\SDK`)
- [x] Install the **Flutter SDK** to `D:\Flutter` and add it to PATH
- [x] Run `flutter doctor` and fix any issues
- [x] Create a **Firebase project** (console.firebase.google.com)
  - Project ID: `daily-attendance-b1b1e` · Spark (free) plan
  - Authentication: Phone enabled on 2026-11-27 (Phase 9; Email/Password was used before)
  - Firestore: `(default)` database, Standard edition, `asia-south2 (Delhi)`, production mode
- [ ] On the Android phone: turn on **Developer options** and **USB debugging** (deferred: testing on the emulator `Medium_Phone_API_37.0` until before Phase 5)

**Done when:** a sample Flutter app runs on the phone.

### Phase 1: Project foundation
- [x] Create the Flutter project in this folder (app ID: `com.dailyattendance.app`)
- [x] Connect the app to Firebase (Authentication + Firestore). Verified on the emulator; real phone still to test
- [x] Set up the folder structure, app theme (purple + blue) and navigation (placeholder screens for each role)

**Done when:** an empty app with the "Daily Attendance" name runs on the emulator (phone later) and is connected to Firebase.

### Phase 2: Login and roles
- [x] Login screen with a Supervisor / Director switch (replaced later by phone login, see Phase 9)
- [x] Director sign-up that creates the company
- [x] Open the director dashboard or the supervisor home depending on role
- [x] First version of the Firestore security rules (deployed; tested in [firestore_tests/](firestore_tests/))
- [x] Check on the emulator: Director sign-up shows the director dashboard
- [x] Check on the emulator: supervisor login (checked in Phase 3, with a supervisor added from the app)

**Done when:** the director and a test supervisor log in and land on different screens.


### Phase 3: Company setup (Director)
- [x] Create / rename / delete teams (a team with employees can't be deleted; deleting one takes it off its supervisors)
- [x] Add supervisors and assign them one or more teams (now by mobile number)
- [x] Edit a supervisor's name and teams; deactivate / reactivate a supervisor
- [x] Settings screen: company name, office hours, late cutoff, half-day hours, edit window
- [x] Security rules for teams and supervisors (tested in [firestore_tests/](firestore_tests/))
- [x] Deploy the updated security rules
- [x] Check on the emulator: add a team and a supervisor as director, then log in as that supervisor

**Done when:** the director has set up all teams and supervisors in the app.

<details>
<summary>How adding a supervisor works</summary>

The director saves the supervisor's profile under their mobile number (`users/{phone}`). No login is created in advance: the first time the supervisor logs in with that number and the SMS code, the app finds the profile waiting for them. The security rules refuse a number that's already in the app, in any company.
</details>

### Phase 4: Employees (supervisor)
- [x] Add / edit / deactivate employees (Emp ID, name, designation). The Emp ID is unique in the company and can't be changed after adding; employees are never deleted, only deactivated
- [x] Monthly team lists: the supervisor picks who works in each team for the month, and the next month starts as a copy. People can be added (new, or "From another team") or taken off during the month. Past months are view only; next month can be planned ahead
- [x] Team selector for supervisors with several teams (one team: just its name)
- [x] Security rules for employees and monthly lists: a supervisor changes only their own teams' lists, for this month or next (tested in [firestore_tests/](firestore_tests/))
- [x] Deploy the updated security rules
- [x] Check on the emulator: log in as a supervisor with two teams, add employees to each, put one person on both lists, check the next month starts with the same people

**Done when:** every team has its employee list.

### Phase 5: Daily attendance (core feature)
- [x] Today's Attendance screen with a team selector. It lists the team's monthly list, so the supervisor doesn't pick people each day
- [x] A worker lent to another team for the day: that team's supervisor adds them to the day's sheet ("Add someone from another team") and marks them present; they then show automatically as absent on their own team's sheet, labelled "Working in Team B"
- [x] Status buttons: Present / Absent / Half-day / Leave, plus "Mark everyone present" / "Mark the rest present"
- [x] In/out time pickers. Present starts at the office start time; "Out time for all" sets one out time for everyone without one
- [x] Automatic hours worked and late flag. A day shorter than the half-day hours becomes a half-day automatically
- [x] "All my teams" done/pending status (on the team selector)
- [x] Edit past days (the edit window from Settings, 7 days by default) on the Past days tab; older days are view only for supervisors
- [x] Security rules for attendance: a supervisor saves only their own teams' sheets, within the edit window; the director any (tested in [firestore_tests/](firestore_tests/))
- [x] Deploy the updated security rules
- [x] Check on the emulator: mark a team, save, lend a worker to a second team, correct yesterday from Past days

**Done when:** a supervisor can fully replace the paper register. ✅ *First usable version.*

### Phase 6: Director dashboard
- [x] Today's overview per team (present / absent / pending), plus whole-company totals that count each person once. Step back to any earlier day with the arrows or the calendar
- [x] Team view: that day's full log. It's the supervisors' sheet with every team to switch to, and the director can correct any day up to today (no edit window)
- [x] Employee history for any date range (up to a year at a time): days present, half-days, absent, leave, late marks, hours, and each day's team and times
- [x] Check on the emulator: as director, see today's counts, open a team, correct a day older than 7 days, look up one person's history

**Done when:** the director can monitor all attendance from the phone.

### Phase 7: Monthly reports
- [x] Monthly summary per employee (present, absent, half-days, leaves, late marks, total hours) on the director's Reports tab. Opens on last month; step to any month, or pick any dates. Lists everyone a team marked, plus active people on a team list with nothing marked
- [x] Dihadi: the firm's hours table, total per employee and for everyone. Warns about days with a missing in or out time
- [x] Export to an Excel file laid out like the firm's sheet: summary tab, all employees' blocks on one sheet (a printed page each), one tab per employee. The director types each daily rate once on the Summary tab; Amount, D\*A and pay totals are Excel formulas that fill in from it
- [ ] Check on the emulator: check Dihadi in Reports against the table, try Custom dates (1–15), share the Excel file, type a rate on the Summary tab and compare with the paper sheet
- [x] Check on the emulator: open Reports, step through months, share the Excel file and open it in a spreadsheet app

**Done when:** the director can process salaries from the report.

### Phase 8: Testing and release
- [x] Confirm the timing rules with the firm (what counts as a full day and a half-day, breaks, minimum hours) and update the app to match (see "Pay rule: Dihadi")
- [x] Finalise and test the security rules with sample data (re-tested and re-published for phone login in Phase 9)
- [ ] Create the app signing key and **back it up safely** (it can't be recovered, and without it you can't release updates)
- [ ] Build the release APK
- [ ] Share the APK through one trusted channel (e.g. a Google Drive link)
- [ ] Help supervisors install it

**Done when:** supervisors are using the app and the paper register is no longer needed.

### Phase 9: Changes after the first demo
Requested by the director after seeing the app. Every change made after Phase 8 is recorded here.
- [x] "CEO" renamed to **Director** everywhere: screens, Excel, code, the saved role (`director`), security rules
- [x] **Phone login** for directors and supervisors: mobile number + SMS code. No more email/password, company code, username or PIN
- [x] A new number is offered "Set up a new company"; a supervisor the director hasn't added yet is told to ask for it
- [x] Supervisors are added by mobile number
- [x] Security rules and tests updated (profiles keyed by phone number; 53 tests in [firestore_tests/](firestore_tests/))
- [x] SHA-1/SHA-256 fingerprints added to the Firebase Android app, debug and release (2026-11-27, with the Firebase CLI; `google-services.json` unchanged)
- [x] Firebase console: Phone sign-in turned on (2026-11-27), with test numbers for trying out the app (kept in the console only, not in this public repo). Test numbers send no SMS
- [ ] Before the firm uses the app for real: delete the test numbers (Authentication → Sign-in method → Phone) and the test company, and turn off Email/Password
- Note: on the free (Spark) plan Firebase sends at most **10 real SMS codes a day**. People stay logged in, so a code is only needed on a new phone, after a reinstall or after logging out. For more, add a billing account (Blaze plan); extra SMS are charged per message
- [x] Delete the old test data (`users`/`companies`/`companyCodes`, all of Firestore, 2026-11-27) and publish the new rules
- [ ] Delete the old email logins (Firebase console → Authentication → Users). Optional: they can't get into the phone-only app
- [ ] Check on the emulator / phone: set up a company with a test number, add a supervisor by number, log in as them
- [x] **Only the director adds, edits or deactivates employees** (app and security rules; rules published). The director has an Employees tab for every team; supervisors only put existing staff on or off their own teams' lists, and see details read-only
- [ ] Check on the phone: director adds an employee; a supervisor's "Add to team" offers only existing staff
- [x] **"Manager" renamed to Supervisor** everywhere (director's request): screens, Excel, code and folders (`lib/features/supervisor/`), the saved role (`supervisor`), the edit-window setting (`supervisorEditDays`), security rules and tests. App tests pass
- [x] Publish the renamed security rules, and remove the old records saved with the role `manager` (all test data deleted 2026-11-27)
- [x] Fixed the rules test "adding a new employee and putting them on a list in one batch": it now expects a supervisor to be refused and the director allowed (all 56 rules tests pass)
- [ ] Check on the phone: the director's People tab lists supervisors; add a supervisor and log in as them
- [x] **Accountant role** (director's request), the link between supervisors and the director, view only:
  - New role `accountant` in the app and the security rules
  - The director adds, edits and deactivates accountants by mobile number on the People tab ("Add" → Accountant), the same way as a supervisor but with no teams. They're listed under "Accountants"
  - The accountant's app reuses the director's screens with every edit button hidden: Dashboard (team sheets open view only, plus employee history), Teams (no add, rename or delete) and Reports (with the Excel export). No Employees, People or Settings tabs
  - No save button anywhere for the accountant. The rules also give them no write access: they can read their company's data and profiles, nothing else
  - Tests: the director adds and edits an accountant, and the accountant's screens are view only (app tests); the director adds and edits an accountant, and an accountant can read their firm (3 rules tests)
- [x] The director's **Supervisors tab renamed "People"**: it lists supervisors and accountants in their own sections, with one "Add" button (Supervisor or Accountant)
- [x] Publish the updated security rules (accountant role), 2026-11-27
- [ ] Check on the phone: the director adds an accountant; log in as them and check Dashboard, Teams and Reports are view only, and the Excel file shares

#### Director's second set of requests (2026-11-27)
- [x] **Entry time:** every person's entry saves when it was marked (Firebase server time, so a changed phone clock can't fake it), who marked it (number and name) and where. Each row shows "Marked 9:42 AM by Sunita". Only new or changed entries get a new stamp; the rest keep theirs
- [x] **Photos** (package `image_picker`): the director adds, changes or removes a photo on the employee form (Take photo or Gallery). Photos are shrunk on the phone to 240 px (about 10–20 KB) and saved on the employee record in Firestore, so no paid Storage plan is needed. Employees still **don't log in**
  - The photo shows next to the name on the Employees tab, the pickers, employee history and reports
  - On the supervisor's marking screen the photo is larger, with a ring in the colour it's marked (helps a supervisor who can't read names). Tap a photo to see it full size
  - Supervisors see an employee's photo but can't change it
- [x] **My profile** (button at the top right on every home screen, showing your photo once added): full name, the mobile number registered with the app, role, and photo. Everyone (director, supervisor, accountant) can take or remove their own photo there. The director can also set a supervisor's or accountant's photo on the People form
  - Rules: `photo` (bytes, at most 100 KB) on employees (director only) and on profiles (the director for their staff; each person for their own photo, nothing else, while active). 61 rules tests pass, 99 app tests pass
- [ ] Check on the phone: add an employee photo with the camera, see it on the supervisor's sheet; add your own photo on My profile
- [x] **Location of each entry:** when a supervisor saves attendance, the phone's GPS position is read once and saved on each new or changed entry. Never tracked in the background; the app explains this before Android's "Allow location?" prompt
  - If location is off or refused, **saving is blocked** (the marks are kept) until the supervisor turns it on. The director's own corrections don't need a location
  - The director and accountant see on each row the distance from the office and a **Map** link (opens Google Maps, no API key). Entries further than the limit, or that Android reports as coming from a location-faking app, are shown in red
  - Settings → **Office location**: "Use where I am now" (stand in the office), Remove, and "Flag entries further than" (default 200 m, 100 m–2 km; GPS indoors can be off by 20–100 m)
  - Packages `geolocator` and `url_launcher`; Android location permission added
  - Rules: settings may hold `office` {lat, lng} and `officeRadiusM` (100–2000). 57 rules tests pass, 93 app tests pass
- [ ] Check on the phone: set the office location, save as a supervisor, see the time, distance and map link as the director; try with location off
- [x] **Custom role names:** Settings → **Names in the app**: the director types the company's own word for Director, Supervisor, Accountant and Employee (e.g. Owner, Foreman, Munim, Worker; up to 30 characters). Blank keeps the usual name, so every company starts with the defaults
  - Every screen follows them live (tab names, headings, buttons, messages, My profile) and so does the Excel file ("All workers" tab). Default words stay lower case mid-sentence ("ask your director"); a firm's own word is kept as typed ("ask your Seth-ji"). Plurals are made by simple English rules (Foreman → Foremen, Mistry → Mistries)
  - Only the names on screen change: the saved roles (`director`, `supervisor`, `accountant`) and the rules stay the same. The login and company set-up screens use the defaults (no company is known yet)
  - Stored as `settings.roleNames` (only the renamed ones). 62 rules tests pass, 106 app tests pass
- [ ] Check on the phone: rename Supervisor and Employee in Settings, then look at a supervisor's tabs and the Excel file
- [x] Security rules published (2026-11-27): office location, photos and role names

#### Later: daily pay in the app (planned, not started)
The app now works out Dihadi; the daily rate is typed by the director in the Excel file. The plan to keep rates in the app:
- [ ] Store each worker's **daily rate** in a separate, director-only place (`companies/{id}/rates/{empId}`), never on the employee record, so supervisors can't see pay. Add rules checks (a positive number) and tests, then publish the rules
- [ ] "Daily rate (₹)" field on the director's employee form; supervisors never see it
- [ ] Reports: pay per person (Dihadi × rate) and a total; someone with no rate is flagged
- [ ] Excel: the Summary tab's rate cells come filled in (still editable there for one-offs)
- Start simple: one **current rate** per worker. If rates change mid-month often, later keep dated rates ("₹550 from 15 Nov") so each day is paid at the rate it had
- Not included: advances, deductions, bonuses

**Done when:** the director's requested changes are working on the phone. New points from the director are added to this list.

### Milestones
```
Phase 0 → 1 → 2 → 3 → 4 → 5   ← usable app (paper register replaced)
                         → 6 → 7   ← director dashboard + payroll ready
                              → 8   ← live in the firm
                                   → 9   ← director's changes after the demo
```

---

## Distribution (APK)

- The app is shared as an **APK file** (the Android installer file) instead of through the Play Store, which is free and needs no review.
- Supervisors open the file, allow "Install unknown apps" once for that source (e.g. Drive), then install.
- Updates: share a new APK and install it over the old one. Data is kept because it's stored online.
- Share it only through one trusted channel, and tell supervisors not to install copies forwarded by others.
- APKs work on **Android only**. If anyone uses an iPhone, a web version can be built from the same Flutter code.
- The app can move to the Play Store later ($25 one-time fee) without code changes.

## Future ideas (not in the first version)

- Reminder notification for supervisors to mark attendance
- Web version for iPhone users / desktop
- Leave requests and approvals
- Holiday calendar

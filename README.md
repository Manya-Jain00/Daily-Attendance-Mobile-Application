# Daily Attendance App

A mobile app that replaces the paper attendance register in a firm. Managers record each employee's daily attendance and in/out times, and the director sees every team's records and uses the monthly report for salaries.

- **Platform:** Android app, shared directly as an APK (no Play Store needed)
- **Tech stack:** Flutter (app) + Firebase (login and online database)
- **Users:** Director / top-level admins and managers. Employees do not log in.


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
| **Director (Super Admin)** | See and edit all teams' attendance, create teams, add managers, **add, edit and deactivate employees** (only the director can), change settings, export monthly reports. Logs in with their **mobile number + SMS code**. |
| **Manager (Team Admin)** | Put existing employees on or off their teams' monthly lists, and mark daily attendance, for **their own teams only**. Can't add new employees, change their details or deactivate them. One manager can handle **several teams**, and one team can have several managers. Logs in with their **mobile number + SMS code**, the number the director added them with. |
| **Employee** | No login. A record (Emp ID, name, designation) that managers mark attendance for. Which team someone works in is set **month by month**: each team has a monthly list of people (see below). Someone can be on more than one team's list. |

## Company structure

```
Company
 ├── Marketing  → Manager(s) → Employees
 ├── Finance    → Manager(s) → Employees
 └── Legal      → Manager(s) → Employees
```

---

## App flow

### 1. One-time setup (Director)
```
Install app → Log in with mobile number + SMS code
   → A number not in any company yet is offered "Set up a new company"
     (company name + your name) and becomes its director
   → Create teams (Marketing, Finance, Legal…)
   → Add managers (name + mobile number) and assign each one or more teams
   → Set office rules (office hours, late cutoff, half-day rule)
```

### 2. Manager setup
```
Install app → Log in with the mobile number the director added + the SMS code
   → Add employees to each of their teams (Emp ID, name, designation)
```

### 3. Daily attendance (manager)
```
Open app → Today's Attendance → pick a team from the selector
   For each employee:
      Status: Present / Absent / Half-day / Leave
      In time / Out time
   → Hours worked and the "Late" flag are calculated automatically
   → Save → data goes online instantly → switch to the next team
```
- The "All my teams" view shows which teams are done and which are pending today.
- Managers can edit the **last 7 days**. Only the director can change older records.
- There are no passwords or PINs to forget: each login on a new phone gets a fresh SMS code.
- A manager who changes their number is added again with the new number (and the old entry deactivated), then given their teams back.

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
| Manager edit window | Last 7 days |

---

## Data structure (Firebase Firestore)

| Path | Stores |
|---|---|
| **users/{phone}** | Director/managers: company ID, role, name, phone, list of team IDs, active. Keyed by the mobile number in international form (`+919876543210`), which is also what the login token carries, so the app finds the company right after login and a director can add a manager before they ever log in. One number belongs to one company |
| **companies/{companyId}** | Name, creator's number, office rules (`settings`) |
| **companies/{companyId}/teams** | Team name. Who manages a team is stored on each manager (`teamIds` in **users**), so the two can't disagree |
| **companies/{companyId}/employees** | Keyed by Emp ID (so IDs are unique in the company): Emp ID, name, designation (optional), active/inactive. Every manager can read the staff list and keep the details up to date |
| **companies/{companyId}/rosters** | Each team's monthly list of people, keyed `{teamId}_{yyyy-MM}`: team, month, Emp IDs. A month with no list of its own uses the latest earlier month's, so a new month automatically starts with last month's people. Managers change their own teams' lists for this month or next; older ones only the director |
| **companies/{companyId}/attendance** | One sheet per team per day, keyed `{teamId}_{yyyy-MM-dd}`: team, date, an entry per employee (status, in/out time, minutes worked, late flag; `guest` for someone lent from another team for the day; `workingIn` for someone absent because they worked in another team), who saved it last and when. One document per sheet, so a team's day is saved in one go. Every member can read all sheets (to see who was lent where); managers save their own teams' sheets within the edit window. The monthly report adds an employee's teams together |

**Phone login setup** (Firebase console, once per project):
1. Authentication → Sign-in method → turn on **Phone**.
2. Project settings → your Android app → add the **SHA-1 and SHA-256** fingerprints of both the debug key and the release key (`keytool -list -v -keystore <keystore>`, or `./gradlew signingReport` in `android/`). Without them Android can't send codes.
3. For testing without real SMS: Authentication → Sign-in method → Phone → **Phone numbers for testing** (e.g. `+91 90000 00001`, code `123456`). Real SMS beyond the free daily allowance needs the Blaze (pay-as-you-go) plan; the console says so when it's needed.

**Security rules:** managers can change only the teams on their list (they can read the whole company's staff lists and sheets, to see who works where). The director can read and write everything. Nobody can access anything without logging in.
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
2. **Director:** Dashboard · Teams · Managers · Reports · Settings
3. **Manager:** Today's Attendance · My Employees · Past Days

---

## Build phases

Each phase is finished and tested on a real phone before moving to the next.

### Phase 0: Prepare the tools
- [x] Install **Android Studio** and put the Android SDK on the **D: drive** (`D:\Android\SDK`)
- [x] Install the **Flutter SDK** to `D:\Flutter` and add it to PATH
- [x] Run `flutter doctor` and fix any issues
- [x] Create a **Firebase project** (console.firebase.google.com)
  - Project ID: `daily-attendance-b1b1e` · Spark (free) plan
  - Authentication: Phone enabled (was Email/Password before the phone-login change)
  - Firestore: `(default)` database, Standard edition, `asia-south2 (Delhi)`, production mode
- [ ] On the Android phone: turn on **Developer options** and **USB debugging** (deferred: testing on the emulator `Medium_Phone_API_37.0` until before Phase 5)

**Done when:** a sample Flutter app runs on the phone.

### Phase 1: Project foundation
- [x] Create the Flutter project in this folder (app ID: `com.dailyattendance.app`)
- [x] Connect the app to Firebase (Authentication + Firestore). Verified on the emulator; real phone still to test
- [x] Set up the folder structure, app theme (purple + blue) and navigation (placeholder screens for each role)

**Done when:** an empty app with the "Daily Attendance" name runs on the emulator (phone later) and is connected to Firebase.

### Phase 2: Login and roles
- [x] Login screen with a Manager / Director switch (replaced later by phone login, see "Changes after the first demo")
- [x] Director sign-up that creates the company
- [x] Open the director dashboard or the manager home depending on role
- [x] First version of the Firestore security rules (deployed; tested in [firestore_tests/](firestore_tests/))
- [x] Check on the emulator: Director sign-up shows the director dashboard
- [x] Check on the emulator: manager login (checked in Phase 3, with a manager added from the app)

**Done when:** the director and a test manager log in and land on different screens.


### Phase 3: Company setup (Director)
- [x] Create / rename / delete teams (a team with employees can't be deleted; deleting one takes it off its managers)
- [x] Add managers and assign them one or more teams (now by mobile number)
- [x] Edit a manager's name and teams; deactivate / reactivate a manager
- [x] Settings screen: company name, office hours, late cutoff, half-day hours, edit window
- [x] Security rules for teams and managers (tested in [firestore_tests/](firestore_tests/))
- [x] Deploy the updated security rules
- [x] Check on the emulator: add a team and a manager as director, then log in as that manager

**Done when:** the director has set up all teams and managers in the app.

<details>
<summary>How adding a manager works</summary>

The director saves the manager's profile under their mobile number (`users/{phone}`). No login is created in advance: the first time the manager logs in with that number and the SMS code, the app finds the profile waiting for them. The security rules refuse a number that's already in the app, in any company.
</details>

### Phase 4: Employees (manager)
- [x] Add / edit / deactivate employees (Emp ID, name, designation). The Emp ID is unique in the company and can't be changed after adding; employees are never deleted, only deactivated
- [x] Monthly team lists: the manager picks who works in each team for the month, and the next month starts as a copy. People can be added (new, or "From another team") or taken off during the month. Past months are view only; next month can be planned ahead
- [x] Team selector for managers with several teams (one team: just its name)
- [x] Security rules for employees and monthly lists: a manager changes only their own teams' lists, for this month or next (tested in [firestore_tests/](firestore_tests/))
- [x] Deploy the updated security rules
- [x] Check on the emulator: log in as a manager with two teams, add employees to each, put one person on both lists, check the next month starts with the same people

**Done when:** every team has its employee list.

### Phase 5: Daily attendance (core feature)
- [x] Today's Attendance screen with a team selector. It lists the team's monthly list, so the manager doesn't pick people each day
- [x] A worker lent to another team for the day: that team's manager adds them to the day's sheet ("Add someone from another team") and marks them present; they then show automatically as absent on their own team's sheet, labelled "Working in Team B"
- [x] Status buttons: Present / Absent / Half-day / Leave, plus "Mark everyone present" / "Mark the rest present"
- [x] In/out time pickers. Present starts at the office start time; "Out time for all" sets one out time for everyone without one
- [x] Automatic hours worked and late flag. A day shorter than the half-day hours becomes a half-day automatically
- [x] "All my teams" done/pending status (on the team selector)
- [x] Edit past days (the edit window from Settings, 7 days by default) on the Past days tab; older days are view only for managers
- [x] Security rules for attendance: a manager saves only their own teams' sheets, within the edit window; the director any (tested in [firestore_tests/](firestore_tests/))
- [x] Deploy the updated security rules
- [x] Check on the emulator: mark a team, save, lend a worker to a second team, correct yesterday from Past days

**Done when:** a manager can fully replace the paper register. ✅ *First usable version.*

### Phase 6: Director dashboard
- [x] Today's overview per team (present / absent / pending), plus whole-company totals that count each person once. Step back to any earlier day with the arrows or the calendar
- [x] Team view: that day's full log. It's the managers' sheet with every team to switch to, and the director can correct any day up to today (no edit window)
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
- [x] Finalise and test the security rules with sample data (53 tests in `firestore_tests` after the phone-login change; publish again after that change)
- [ ] Create the app signing key and **back it up safely** (it can't be recovered, and without it you can't release updates)
- [ ] Build the release APK
- [ ] Share the APK through one trusted channel (e.g. a Google Drive link)
- [ ] Help managers install it

**Done when:** managers are using the app and the paper register is no longer needed.

### Changes after the first demo
- [x] "CEO" renamed to **Director** everywhere: screens, Excel, code, the saved role (`director`), security rules
- [x] **Phone login** for directors and managers: mobile number + SMS code. No more email/password, company code, username or PIN
- [x] A new number is offered "Set up a new company"; a manager the director hasn't added yet is told to ask for it
- [x] Managers are added by mobile number
- [x] Security rules and tests updated (profiles keyed by phone number)
- [ ] Firebase console: turn on Phone sign-in, add SHA-1/SHA-256 (debug + release), add test numbers
- [ ] Delete the old test data (old email logins and `users`/`companies`/`companyCodes` documents) and publish the new rules
- [ ] Check on the emulator / phone: set up a company with a test number, add a manager by number, log in as them

### Milestones
```
Phase 0 → 1 → 2 → 3 → 4 → 5   ← usable app (paper register replaced)
                         → 6 → 7   ← director dashboard + payroll ready
                              → 8   ← live in the firm
```

---

## Distribution (APK)

- The app is shared as an **APK file** (the Android installer file) instead of through the Play Store, which is free and needs no review.
- Managers open the file, allow "Install unknown apps" once for that source (e.g. Drive), then install.
- Updates: share a new APK and install it over the old one. Data is kept because it's stored online.
- Share it only through one trusted channel, and tell managers not to install copies forwarded by others.
- APKs work on **Android only**. If anyone uses an iPhone, a web version can be built from the same Flutter code.
- The app can move to the Play Store later ($25 one-time fee) without code changes.

## Future ideas (not in the first version)

- Reminder notification for managers to mark attendance
- Web version for iPhone users / desktop
- Leave requests and approvals
- Holiday calendar

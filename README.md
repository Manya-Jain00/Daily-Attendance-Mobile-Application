# Daily Attendance App

A mobile app that replaces the paper attendance register in a firm. Managers record each employee's daily attendance and in/out times, and the CEO sees every team's records and uses the monthly report for salaries.

- **Platform:** Android app, shared directly as an APK (no Play Store needed)
- **Tech stack:** Flutter (app) + Firebase (login and online database)
- **Users:** CEO / top-level admins and managers. Employees do not log in.


## Running it yourself

The Firebase config files (`android/app/google-services.json` and `lib/firebase_options.dart`) are not in this repo. To build the app, create your own Firebase project (Authentication with Email/Password, plus Firestore), then run:

```
dart pub global activate flutterfire_cli
flutterfire configure
flutter run
```

---

## Roles

| Role | Can do |
|---|---|
| **CEO (Super Admin)** | See and edit all teams' attendance, create teams, add managers, change settings, export monthly reports. There can be more than one. Logs in with **email + password**. |
| **Manager (Team Admin)** | Add employees and mark daily attendance for **their own teams only**. One manager can handle **several teams**, and one team can have several managers. Logs in with **company code + username + PIN**, so no email is needed. |
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

### 1. One-time setup (CEO)
```
Install app → Sign up → Create company
   → The app gives the company a 6-character company code (e.g. K7RM2Q),
     shown on the CEO dashboard
   → Create teams (Marketing, Finance, Legal…)
   → Add managers (name + username + PIN) and assign each one or more teams
   → Set office rules (office hours, late cutoff, half-day rule)
```

### 2. Manager setup
```
Install app → Log in (Manager tab) with the company code, username and PIN from the CEO
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
- Managers can edit the **last 7 days**. Only the CEO can change older records.
- A manager who forgets their PIN asks the CEO, who deactivates them and adds them again with a new username and PIN, then gives them their teams back. (There's no reset email, because managers don't need an email.)

### 4. CEO dashboard
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
The report shows, per employee: days present, absent, half-days, leaves, late marks, hours and **Dihadi** (days' pay earned, see below). The app doesn't store pay rates: in the Excel file the CEO types each worker's daily rate once on the Summary tab, and the Amount, D\*A and pay totals fill in by themselves. The Excel file has a summary tab, an "All employees" sheet with each worker's block (one row per day, yellow total; a printed page each), and one tab per worker.

## Pay rule: Dihadi

Each day's hours earn a share of a day's pay, the **Dihadi**. Pay = total Dihadi × the worker's daily rate (typed by the CEO in the Excel file).

| Hours | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Dihadi | 0.125 | 0.25 | 0.5 | 0.5 | 0.625 | 0.75 | 0.875 | 1 | 1 | 1.25 | 1.25 | 1.5 | 1.625 | 1.75 | 1.75 | 2 |

- Hours are rounded to the nearest half hour (8 h 15 m → 8 h 30 m; 8 h 14 m → 8 h). A half hour adds 0.0625 (8 h 30 m and 9 h 30 m → 1.0625).
- Past 16 hours, each hour adds 0.125.
- Absent and leave earn 0. Late marks are shown but don't reduce pay.
- A day with an in or out time missing earns 0 and is flagged, so it can be fixed.
- The rule is in [day_value.dart](lib/core/models/day_value.dart).

---

## Default rules (the CEO can change these in Settings)

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
| **users/{uid}** | CEO/managers: company ID, company code, role, name, email, username (managers), list of team IDs, active. Keyed by the login's uid so the app finds the company right after login |
| **companies/{companyId}** | Name, company code (`code`), creator, office rules (`settings`) |
| **companyCodes/{code}** | Which company a code belongs to. Claimed once at sign-up so no two firms get the same code |
| **companies/{companyId}/teams** | Team name. Who manages a team is stored on each manager (`teamIds` in **users**), so the two can't disagree |
| **companies/{companyId}/employees** | Keyed by Emp ID (so IDs are unique in the company): Emp ID, name, designation (optional), active/inactive. Every manager can read the staff list and keep the details up to date |
| **companies/{companyId}/rosters** | Each team's monthly list of people, keyed `{teamId}_{yyyy-MM}`: team, month, Emp IDs. A month with no list of its own uses the latest earlier month's, so a new month automatically starts with last month's people. Managers change their own teams' lists for this month or next; older ones only the CEO |
| **companies/{companyId}/attendance** | One sheet per team per day, keyed `{teamId}_{yyyy-MM-dd}`: team, date, an entry per employee (status, in/out time, minutes worked, late flag; `guest` for someone lent from another team for the day; `workingIn` for someone absent because they worked in another team), who saved it last and when. One document per sheet, so a team's day is saved in one go. Every member can read all sheets (to see who was lent where); managers save their own teams' sheets within the edit window. The monthly report adds an employee's teams together |

**Manager logins:** Firebase needs an email for every login, so each manager gets a hidden one made from their username and company code, e.g. `ravi@k7rm2q.login.daily-attendance-b1b1e.firebaseapp.com`. Managers never see or type it; nothing is ever sent to it.

**Security rules:** managers can change only the teams on their list (they can read the whole company's staff lists and sheets, to see who works where). The CEO can read and write everything. Nobody can access anything without logging in.
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
- Security rules keep firms completely separate: a CEO's "everything" means everything **in their own company**.
- Each new firm signs up through the same CEO sign-up flow and creates its own company.

## Screens

1. **Login**
2. **CEO:** Dashboard · Teams · Managers · Reports · Settings
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
  - Authentication: Email/Password enabled
  - Firestore: `(default)` database, Standard edition, `asia-south2 (Delhi)`, production mode
- [ ] On the Android phone: turn on **Developer options** and **USB debugging** (deferred: testing on the emulator `Medium_Phone_API_37.0` until before Phase 5)

**Done when:** a sample Flutter app runs on the phone.

### Phase 1: Project foundation
- [x] Create the Flutter project in this folder (app ID: `com.dailyattendance.app`)
- [x] Connect the app to Firebase (Authentication + Firestore). Verified on the emulator; real phone still to test
- [x] Set up the folder structure, app theme (purple + blue) and navigation (placeholder screens for each role)

**Done when:** an empty app with the "Daily Attendance" name runs on the emulator (phone later) and is connected to Firebase.

### Phase 2: Login and roles
- [x] Login screen with a Manager / CEO switch: managers use company code + username + PIN, CEOs use email + password with "Forgot password?" reset email
- [x] CEO sign-up that creates the company and its company code (shown on the CEO dashboard)
- [x] Open the CEO dashboard or the manager home depending on role
- [x] First version of the Firestore security rules (deployed; tested in [firestore_tests/](firestore_tests/))
- [x] Check on the emulator: CEO sign-up shows the CEO dashboard and company code
- [x] Check on the emulator: manager login (checked in Phase 3, with a manager added from the app)

**Done when:** the CEO and a test manager log in and land on different screens.


### Phase 3: Company setup (CEO)
- [x] Create / rename / delete teams (a team with employees can't be deleted; deleting one takes it off its managers)
- [x] Add managers (name, username, PIN) and assign them one or more teams; the app shows the login details to hand over once
- [x] Edit a manager's name and teams; deactivate / reactivate a manager
- [x] Settings screen: company name, office hours, late cutoff, half-day hours, edit window
- [x] Security rules for teams and managers (tested in [firestore_tests/](firestore_tests/))
- [x] Deploy the updated security rules
- [x] Check on the emulator: add a team and a manager as CEO, then log in as that manager

**Done when:** the CEO has set up all teams and managers in the app.

<details>
<summary>How adding a manager works (free Spark plan)</summary>

Firebase can only create a login by signing in as it, which would log the CEO out. So the app creates the manager's login on a second, background connection to Firebase, then saves the manager's profile as the CEO. The PIN is never stored in the database; the CEO sees it once, when the manager is added.
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
- [x] Security rules for attendance: a manager saves only their own teams' sheets, within the edit window; the CEO any (tested in [firestore_tests/](firestore_tests/))
- [x] Deploy the updated security rules
- [x] Check on the emulator: mark a team, save, lend a worker to a second team, correct yesterday from Past days

**Done when:** a manager can fully replace the paper register. ✅ *First usable version.*

### Phase 6: CEO dashboard
- [x] Today's overview per team (present / absent / pending), plus whole-company totals that count each person once. Step back to any earlier day with the arrows or the calendar
- [x] Team view: that day's full log. It's the managers' sheet with every team to switch to, and the CEO can correct any day up to today (no edit window)
- [x] Employee history for any date range (up to a year at a time): days present, half-days, absent, leave, late marks, hours, and each day's team and times
- [x] Check on the emulator: as CEO, see today's counts, open a team, correct a day older than 7 days, look up one person's history

**Done when:** the CEO can monitor all attendance from the phone.

### Phase 7: Monthly reports
- [x] Monthly summary per employee (present, absent, half-days, leaves, late marks, total hours) on the CEO's Reports tab. Opens on last month; step to any month, or pick any dates. Lists everyone a team marked, plus active people on a team list with nothing marked
- [x] Dihadi: the firm's hours table, total per employee and for everyone. Warns about days with a missing in or out time
- [x] Export to an Excel file laid out like the firm's sheet: summary tab, all employees' blocks on one sheet (a printed page each), one tab per employee. The CEO types each daily rate once on the Summary tab; Amount, D\*A and pay totals are Excel formulas that fill in from it
- [ ] Check on the emulator: check Dihadi in Reports against the table, try Custom dates (1–15), share the Excel file, type a rate on the Summary tab and compare with the paper sheet
- [x] Check on the emulator: open Reports, step through months, share the Excel file and open it in a spreadsheet app

**Done when:** the CEO can process salaries from the report.

### Phase 8: Testing and release
- [x] Confirm the timing rules with the firm (what counts as a full day and a half-day, breaks, minimum hours) and update the app to match (see "Pay rule: Dihadi")
- [x] Finalise and test the security rules with sample data (57 tests in `firestore_tests`; published to the live project)
- [ ] Create the app signing key and **back it up safely** (it can't be recovered, and without it you can't release updates)
- [ ] Build the release APK
- [ ] Share the APK through one trusted channel (e.g. a Google Drive link)
- [ ] Help managers install it

**Done when:** managers are using the app and the paper register is no longer needed.

### Milestones
```
Phase 0 → 1 → 2 → 3 → 4 → 5   ← usable app (paper register replaced)
                         → 6 → 7   ← CEO dashboard + payroll ready
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

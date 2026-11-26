import 'package:material_ui/material_ui.dart';

import '../../core/data/company_repository.dart';
import '../../core/data/employee_repository.dart';
import '../../core/models/attendance.dart';
import '../../core/models/company.dart';
import '../../core/models/day.dart';
import '../../core/models/employee.dart';
import '../../core/models/roster.dart';
import '../../core/models/team_day.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/brand_app_bar.dart';
import '../../shared/widgets/load_state.dart';
import 'employees_page.dart' show initialOf;
import 'pick_guest_page.dart';

/// Whether a supervisor may still change [date]'s attendance: today and the
/// company's edit window before it. Older days are the director's to correct.
bool supervisorMayEdit(Day date, Day today, CompanySettings settings) =>
    !(date > today) && today.daysSince(date) <= settings.supervisorEditDays;

/// Supervisor: one day's attendance sheet for one of their teams. The sheet
/// lists the team's monthly list, so nobody is picked by hand each day.
///
/// Opened from the director's dashboard (with a director [repository]) it offers every
/// team, and any day up to today can be corrected. Opened for an accountant it
/// offers every team too, but is view only: nothing can be marked or saved.
///
/// With no [date] it's the Today tab, and follows the calendar. With a
/// [date] it's a page of its own (opened from Past days).
class AttendancePage extends StatefulWidget {
  const AttendancePage({
    super.key,
    required this.repository,
    this.date,
    this.teamId,
  });

  final EmployeeRepository repository;
  final Day? date;

  /// The team to show first.
  final String? teamId;

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  EmployeeRepository get _repo => widget.repository;

  late final _teams = _repo.watchTeams();
  late final _employees = _repo.watchEmployees();
  late final _settings = _repo.watchSettings();

  late Day _date = widget.date ?? Day.today();
  late Stream<List<Roster>> _rosters;
  late Stream<List<AttendanceSheet>> _sheets;

  /// The team on screen. Null until the teams load.
  late String? _teamId = widget.teamId;

  /// Unsaved changes to the team on screen, or null when there are none.
  Map<String, AttendanceEntry>? _draft;
  bool _saving = false;

  /// The rows and settings as last drawn, for the button handlers.
  List<SheetRow> _rows = const [];
  CompanySettings _rules = CompanySettings.defaults;

  @override
  void initState() {
    super.initState();
    _watchDate();
  }

  void _watchDate() {
    _rosters = _repo.watchRosters(_date.monthOf);
    _sheets = _repo.watchAttendance(_date, _date);
  }

  /// Keeps the chosen team if it's still one of mine. Otherwise starts with
  /// the first team still to be marked.
  String _selectedFrom(List<Team> myTeams, DayData data) {
    final current = _teamId;
    if (current != null && myTeams.any((t) => t.id == current)) return current;
    final pending = myTeams.where((t) => !data.progress(t.id).done);
    return _teamId = (pending.firstOrNull ?? myTeams.first).id;
  }

  // ---- Changes ------------------------------------------------------------

  /// Records [entry] for [empId] (null takes them off the sheet).
  void _set(String empId, AttendanceEntry? entry) {
    final draft = entriesToSave(_rows);
    if (entry == null) {
      draft.remove(empId);
    } else {
      draft[empId] = entry;
    }
    setState(() => _draft = draft);
  }

  void _setMany(Map<String, AttendanceEntry> changes) {
    if (changes.isEmpty) return;
    setState(() => _draft = {...entriesToSave(_rows), ...changes});
  }

  void _mark(SheetRow row, AttendanceStatus status) {
    final old = row.entry;
    if (old?.status == status) return;
    _set(
      row.empId,
      AttendanceEntry.mark(
        status,
        // Starts at office time; the supervisor changes it for late comers.
        inTime: old?.inTime ?? _rules.officeStart,
        outTime: old?.outTime,
        settings: _rules,
        guest: row.guest,
      ),
    );
  }

  /// Everyone not marked yet: present from office time.
  void _markRestPresent() => _setMany({
    for (final row in _rows)
      if (!row.marked)
        row.empId: AttendanceEntry.mark(
          AttendanceStatus.present,
          inTime: _rules.officeStart,
          settings: _rules,
          guest: row.guest,
        ),
  });

  Future<String?> _askTime(
    String helpText,
    String? current,
    String fallback,
  ) async {
    final initial = minutesOf(current) ?? minutesOf(fallback)!;
    final picked = await showTimePicker(
      context: context,
      helpText: helpText,
      initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
    );
    if (picked == null || !mounted) return null;
    return timeOf(picked.hour * 60 + picked.minute);
  }

  Future<void> _pickTime(SheetRow row, {required bool isIn}) async {
    final entry = row.entry;
    if (entry == null) return;
    final value = await _askTime(
      '${isIn ? 'In' : 'Out'} time · ${row.name}',
      isIn ? entry.inTime : entry.outTime,
      isIn ? _rules.officeStart : _rules.officeEnd,
    );
    if (value == null || !mounted) return;
    // Read again: the sheet may have changed while the clock was open.
    final current = _rows.where((r) => r.empId == row.empId).firstOrNull?.entry;
    if (current == null || !current.status.worked) return;
    final inTime = isIn ? value : current.inTime;
    final outTime = isIn ? current.outTime : value;
    final start = minutesOf(inTime);
    final end = minutesOf(outTime);
    if (start != null && end != null && end <= start) {
      showMessage(context, 'The out time must be after the in time.');
      return;
    }
    _set(row.empId, current.withTimes(inTime, outTime, _rules));
  }

  /// One out time for everyone present who doesn't have one yet.
  Future<void> _outTimeForAll() async {
    final value = await _askTime(
      'Out time for everyone without one',
      null,
      _rules.officeEnd,
    );
    if (value == null) return;
    final end = minutesOf(value)!;
    var skipped = 0;
    final changes = <String, AttendanceEntry>{};
    for (final row in _rows) {
      final entry = row.entry;
      if (row.lentTo != null ||
          entry == null ||
          !entry.status.worked ||
          entry.outTime != null) {
        continue;
      }
      final start = minutesOf(entry.inTime);
      if (start != null && end <= start) {
        skipped++;
        continue;
      }
      changes[row.empId] = entry.withTimes(entry.inTime, value, _rules);
    }
    _setMany(changes);
    if (skipped > 0 && mounted) {
      showMessage(
        context,
        skipped == 1
            ? '1 person came in after ${displayTime(value)}; set their out '
                  'time on their own.'
            : '$skipped people came in after ${displayTime(value)}; set their '
                  'out times on their own.',
      );
    }
  }

  Future<void> _addGuest(Team team, DayData data, List<Team> teams) async {
    final onSheet = {for (final r in _rows) r.empId};
    final teamNames = {for (final t in teams) t.id: t.name};
    final picked = await Navigator.of(context).push<Employee>(
      MaterialPageRoute(
        builder: (_) => PickGuestPage(
          teamName: team.name,
          candidates: [
            for (final e in data.employees.values)
              if (e.active && !onSheet.contains(e.empId)) e,
          ]..sort(Employee.compareByEmpId),
          notes: _guestNotes(data, teamNames, team.id),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    _set(
      picked.empId,
      AttendanceEntry.mark(
        AttendanceStatus.present,
        inTime: _rules.officeStart,
        settings: _rules,
        guest: true,
      ),
    );
  }

  /// For each employee: which teams they're on this month, and whether
  /// another team already has them down as working today.
  Map<String, String> _guestNotes(
    DayData data,
    Map<String, String> teamNames,
    String teamId,
  ) {
    final notes = <String, List<String>>{};
    for (final t in teamNames.entries) {
      for (final id in data.listOf(t.key)) {
        (notes[id] ??= []).add('In ${t.value}');
      }
    }
    for (final sheet in data.day.byTeam.values) {
      if (sheet.teamId == teamId) continue;
      sheet.entries.forEach((id, entry) {
        if (entry.status.worked && entry.workingIn == null) {
          (notes[id] ??= []).add(
            'Marked ${entry.status.label.toLowerCase()} in '
            '${teamNames[sheet.teamId] ?? 'another team'} today',
          );
        }
      });
    }
    return {for (final n in notes.entries) n.key: n.value.join(' · ')};
  }

  Future<void> _save(Team team) async {
    if (_draft == null || _saving) return;
    setState(() => _saving = true);
    try {
      await _repo.saveAttendance(team.id, _date, entriesToSave(_rows));
      if (!mounted) return;
      setState(() => _draft = null);
      showMessage(context, '${team.name} saved for ${_date.label}');
    } on DataFailure catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Asks before throwing away unsaved changes. True when there are none
  /// left.
  Future<bool> _confirmDiscard() async {
    if (_draft == null) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text("This sheet has changes that aren't saved yet."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return false;
    setState(() => _draft = null);
    return true;
  }

  Future<void> _switchTeam(String teamId) async {
    if (teamId == _teamId) return;
    if (await _confirmDiscard()) setState(() => _teamId = teamId);
  }

  // ---- Layout -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // The Today tab moves on to the next day by itself (unless the supervisor
    // is in the middle of changes).
    if (widget.date == null && _draft == null) {
      final today = Day.today();
      if (today != _date) {
        _date = today;
        _watchDate();
      }
    }

    final body = StreamBuilder<List<Team>>(
      stream: _teams,
      builder: (context, teamsSnap) => StreamBuilder<List<Employee>>(
        stream: _employees,
        builder: (context, employeesSnap) => StreamBuilder<CompanySettings>(
          stream: _settings,
          builder: (context, settingsSnap) => StreamBuilder<List<Roster>>(
            stream: _rosters,
            builder: (context, rostersSnap) =>
                StreamBuilder<List<AttendanceSheet>>(
                  stream: _sheets,
                  builder: (context, sheetsSnap) {
                    final loading = loadStateFor([
                      teamsSnap,
                      employeesSnap,
                      settingsSnap,
                      rostersSnap,
                      sheetsSnap,
                    ]);
                    if (loading != null) return loading;
                    return _buildLoaded(
                      teams: teamsSnap.data!,
                      settings: settingsSnap.data!,
                      data: DayData(
                        date: _date,
                        sheets: sheetsSnap.data!,
                        rosters: rostersSnap.data!,
                        employees: employeesSnap.data!,
                      ),
                    );
                  },
                ),
          ),
        ),
      ),
    );

    if (widget.date == null) return body;
    return PopScope(
      canPop: _draft == null,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop();
      },
      child: Scaffold(
        appBar: BrandAppBar(title: _date.longLabel),
        body: body,
      ),
    );
  }

  Widget _buildLoaded({
    required List<Team> teams,
    required CompanySettings settings,
    required DayData data,
  }) {
    final isDirector = _repo.isDirector;
    final isAccountant = _repo.isAccountant;
    final seesAllTeams = isDirector || isAccountant;
    final mine = _repo.myTeamIds;
    final myTeams = seesAllTeams
        ? teams
        : teams.where((t) => mine.contains(t.id)).toList();
    if (myTeams.isEmpty) {
      return EmptyState(
        icon: Icons.groups_outlined,
        title: 'No teams yet',
        message: isDirector
            ? 'Add teams on the Teams tab first.'
            : isAccountant
            ? 'The director has not added any teams yet.'
            : 'You have not been given a team yet. Ask your director to assign '
                  'you one.',
      );
    }
    final teamId = _selectedFrom(myTeams, data);
    final team = myTeams.firstWhere((t) => t.id == teamId);
    final teamNames = {for (final t in teams) t.id: t.name};
    final today = Day.today();
    final editable = isAccountant
        ? false
        : isDirector
        ? !(_date > today)
        : supervisorMayEdit(_date, today, settings);

    _rules = settings;
    _rows = data.rows(teamId, _draft);
    final rows = _rows;
    final progress = progressOf(rows);
    final progressByTeam = {
      for (final t in myTeams)
        t.id: t.id == teamId ? progress : data.progress(t.id),
    };

    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    final header = <Widget>[
      if (widget.date == null)
        Text(
          'Today · ${_date.longLabel}',
          style: theme.textTheme.titleSmall?.copyWith(color: muted),
        ),
      _TeamStatusSelector(
        title: seesAllTeams ? 'All teams' : 'All my teams',
        teams: myTeams,
        selectedId: teamId,
        progress: progressByTeam,
        onSelected: _switchTeam,
      ),
      if (!editable)
        _Note(
          icon: Icons.lock_outline,
          text: _date > today
              ? 'This day has not come yet.'
              : isAccountant
              ? 'View only.'
              : 'Older than ${settings.supervisorEditDays} days: view only. Ask '
                    'your director to correct it.',
        ),
      if (rows.isNotEmpty)
        _Summary(
          rows: rows,
          progress: progress,
          unsaved: _draft != null,
          onMarkRestPresent: editable && !progress.done
              ? _markRestPresent
              : null,
          onOutTimeForAll:
              editable &&
                  rows.any(
                    (r) =>
                        r.lentTo == null &&
                        r.entry != null &&
                        r.entry!.status.worked &&
                        r.entry!.outTime == null,
                  )
              ? _outTimeForAll
              : null,
        ),
    ];

    final addGuest = editable
        ? Padding(
            padding: const EdgeInsets.only(top: 4),
            child: OutlinedButton.icon(
              onPressed: () => _addGuest(team, data, teams),
              icon: const Icon(Icons.person_add_alt_outlined),
              label: const Text('Add someone from another team'),
            ),
          )
        : null;

    final Widget list;
    if (rows.isEmpty) {
      list = ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          ...header,
          const SizedBox(height: 8),
          SizedBox(
            height: 260,
            child: EmptyState(
              icon: Icons.people_outline,
              title: 'Nobody on the list',
              message: seesAllTeams
                  ? "${team.name}'s supervisors put people on its list on their "
                        'Employees tab. They then show here every day.'
                  : 'Add the people who work in ${team.name} on the '
                        'Employees tab. They then show here every day.',
            ),
          ),
          ?addGuest,
        ],
      );
    } else {
      final items = <Widget>[
        ...header,
        for (final row in rows)
          _RowCard(
            key: ValueKey(row.empId),
            row: row,
            editable: editable && !_saving,
            lentToName: row.lentTo == null
                ? null
                : teamNames[row.lentTo] ?? 'another team',
            onStatus: (status) => _mark(row, status),
            onInTime: () => _pickTime(row, isIn: true),
            onOutTime: () => _pickTime(row, isIn: false),
            onRemove: row.guest ? () => _set(row.empId, null) : null,
          ),
        ?addGuest,
      ];
      list = ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) => items[i],
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: list,
      bottomNavigationBar: _draft == null
          ? null
          : _SaveBar(
              saving: _saving,
              progress: progress,
              onSave: () => _save(team),
              onDiscard: _saving ? null : _confirmDiscard,
            ),
    );
  }
}

/// The supervisor's teams, each with how far today's sheet has got ("All my
/// teams"). With one team there's nothing to pick, so it just names it.
class _TeamStatusSelector extends StatelessWidget {
  const _TeamStatusSelector({
    required this.title,
    required this.teams,
    required this.selectedId,
    required this.progress,
    required this.onSelected,
  });

  /// "All my teams", or "All teams" for the director.
  final String title;
  final List<Team> teams;
  final String selectedId;
  final Map<String, SheetProgress> progress;
  final ValueChanged<String> onSelected;

  static String statusText(SheetProgress p) {
    if (p.total == 0) return 'Nobody on the list';
    if (p.done) return 'Done';
    return p.marked == 0 ? 'Pending' : '${p.pending} left';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget icon(SheetProgress p, {double size = 18}) => Icon(
      p.done ? Icons.check_circle : Icons.schedule,
      size: size,
      color: p.done ? AppColors.present : AppColors.halfDay,
    );

    if (teams.length == 1) {
      final p = progress[teams.single.id]!;
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Icon(Icons.groups_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                teams.single.name,
                style: theme.textTheme.titleMedium,
              ),
            ),
            icon(p),
            const SizedBox(width: 4),
            Text(statusText(p)),
          ],
        ),
      );
    }

    final done = teams.where((t) => progress[t.id]!.done).length;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title: $done of ${teams.length} done',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final team in teams)
                ChoiceChip(
                  avatar: icon(progress[team.id]!),
                  showCheckmark: false,
                  label: Text(
                    '${team.name} · ${statusText(progress[team.id]!)}',
                  ),
                  selected: team.id == selectedId,
                  onSelected: (_) => onSelected(team.id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "7 of 10 marked · 6 P · 1 A" and the shortcuts for the whole sheet.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.rows,
    required this.progress,
    required this.unsaved,
    required this.onMarkRestPresent,
    required this.onOutTimeForAll,
  });

  final List<SheetRow> rows;
  final SheetProgress progress;
  final bool unsaved;
  final VoidCallback? onMarkRestPresent;
  final VoidCallback? onOutTimeForAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = <AttendanceStatus, int>{};
    var late = 0;
    for (final row in rows) {
      final entry = row.entry;
      if (entry == null) continue;
      counts[entry.status] = (counts[entry.status] ?? 0) + 1;
      if (entry.late) late++;
    }
    final parts = [
      '${progress.marked} of ${progress.total} marked',
      for (final status in AttendanceStatus.values)
        if (counts[status] case final n?) '$n ${status.letter}',
      if (late > 0) '$late late',
      if (unsaved) 'not saved',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text(
          parts.join(' · '),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (onMarkRestPresent != null || onOutTimeForAll != null)
          Wrap(
            spacing: 8,
            children: [
              if (onMarkRestPresent != null)
                TextButton.icon(
                  onPressed: onMarkRestPresent,
                  icon: const Icon(Icons.done_all),
                  label: Text(
                    progress.marked == 0
                        ? 'Mark everyone present'
                        : 'Mark the rest present',
                  ),
                ),
              if (onOutTimeForAll != null)
                TextButton.icon(
                  onPressed: onOutTimeForAll,
                  icon: const Icon(Icons.logout),
                  label: const Text('Out time for all'),
                ),
            ],
          ),
      ],
    );
  }
}

/// One person: status buttons, in/out times, hours and the late flag.
class _RowCard extends StatelessWidget {
  const _RowCard({
    super.key,
    required this.row,
    required this.editable,
    required this.lentToName,
    required this.onStatus,
    required this.onInTime,
    required this.onOutTime,
    required this.onRemove,
  });

  final SheetRow row;
  final bool editable;
  final String? lentToName;
  final ValueChanged<AttendanceStatus> onStatus;
  final VoidCallback onInTime;
  final VoidCallback onOutTime;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final entry = row.entry;
    final employee = row.employee;

    final details = [
      [
        row.empId,
        if (employee != null && employee.designation.isNotEmpty)
          employee.designation,
      ].join(' · '),
      if (row.guest) 'From another team today',
      if (employee != null && !employee.active) 'No longer active',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: entry == null
                      ? theme.colorScheme.surfaceContainerHighest
                      : statusColor(entry.status).withValues(alpha: 0.15),
                  foregroundColor: entry == null
                      ? muted
                      : statusColor(entry.status),
                  child: Text(
                    entry == null ? initialOf(row.name) : entry.status.letter,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row.name, style: theme.textTheme.titleMedium),
                      Text(
                        details.join('\n'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (entry != null && entry.late)
                  const _Tag(text: 'Late', color: AppColors.late),
                if (onRemove != null && editable)
                  IconButton(
                    tooltip: 'Take ${row.name} off this sheet',
                    icon: const Icon(Icons.close),
                    onPressed: onRemove,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (lentToName != null)
              Row(
                children: [
                  Icon(Icons.swap_horiz, size: 20, color: muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Working in $lentToName today (absent here)',
                      style: TextStyle(color: muted),
                    ),
                  ),
                ],
              )
            else ...[
              Row(
                children: [
                  for (final status in AttendanceStatus.values)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: _StatusButton(
                          status: status,
                          selected: entry?.status == status,
                          onPressed: editable ? () => onStatus(status) : null,
                        ),
                      ),
                    ),
                ],
              ),
              if (entry != null && entry.status.worked) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      child: _TimeButton(
                        label: 'In',
                        time: entry.inTime,
                        onPressed: editable ? onInTime : null,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: _TimeButton(
                        label: 'Out',
                        time: entry.outTime,
                        onPressed: editable ? onOutTime : null,
                      ),
                    ),
                    if (entry.minutes != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          displayDuration(entry.minutes!),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    const SizedBox(width: 4),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

Color statusColor(AttendanceStatus status) => switch (status) {
  AttendanceStatus.present => AppColors.present,
  AttendanceStatus.absent => AppColors.absent,
  AttendanceStatus.halfDay => AppColors.halfDay,
  AttendanceStatus.leave => AppColors.leave,
};

class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.status,
    required this.selected,
    required this.onPressed,
  });

  final AttendanceStatus status;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 4),
      ),
      visualDensity: VisualDensity.compact,
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      backgroundColor: WidgetStatePropertyAll(
        selected ? color : Colors.transparent,
      ),
      foregroundColor: WidgetStatePropertyAll(selected ? Colors.white : color),
      side: WidgetStatePropertyAll(
        BorderSide(color: color.withValues(alpha: selected ? 1 : 0.5)),
      ),
    );
    // The colours ignore the disabled state, so a view-only sheet still
    // shows what was marked.
    return Semantics(
      selected: selected,
      child: OutlinedButton(
        style: style,
        onPressed: onPressed,
        child: FittedBox(child: Text(status.label)),
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.time,
    required this.onPressed,
  });

  final String label;
  final String? time;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      onPressed: onPressed,
      icon: Icon(label == 'In' ? Icons.login : Icons.logout, size: 18),
      label: Text(
        '$label ${time == null ? '--:--' : displayTime(time!)}',
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF8D6E00),
        ),
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.saving,
    required this.progress,
    required this.onSave,
    required this.onDiscard,
  });

  final bool saving;
  final SheetProgress progress;
  final VoidCallback onSave;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              TextButton(onPressed: onDiscard, child: const Text('Discard')),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: saving ? null : onSave,
                  icon: saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_outlined),
                  label: Text(
                    progress.done
                        ? 'Save'
                        : 'Save (${progress.pending} not marked)',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

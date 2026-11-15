/// Someone whose attendance is marked, as stored in
/// `companies/{companyId}/employees/{empId}`. Employees don't log in.
///
/// Which team someone works in is decided month by month, by the teams'
/// monthly lists (see `Roster`), not here.
///
/// The document is keyed by the Emp ID, so Firestore itself keeps Emp IDs
/// unique across the company. That's also why the Emp ID can't be changed
/// once the employee is added.
class Employee {
  const Employee({
    required this.empId,
    required this.name,
    this.designation = '',
    this.active = true,
  });

  /// Upper case, e.g. `EMP-014` or `102`.
  final String empId;
  final String name;

  /// Optional, e.g. "Accountant". Empty when not given.
  final String designation;

  /// Inactive employees (people who left) are kept so their past attendance
  /// still has a name, but they're left off new attendance sheets.
  final bool active;

  static const maxEmpIdLength = 20;

  static final _empIdPattern = RegExp(r'^[A-Z0-9][A-Z0-9-]{0,19}$');

  /// Trims and upper-cases, so "emp-1 " and "EMP-1" are the same ID.
  static String normalizeEmpId(String value) => value.trim().toUpperCase();

  /// Letters, digits and dashes, starting with a letter or digit. Checked
  /// after [normalizeEmpId]. (The security rules check the same pattern.)
  static bool isValidEmpId(String value) => _empIdPattern.hasMatch(value);

  /// Returns null when a required field is missing, so a bad record can't
  /// crash the app.
  static Employee? fromMap(String id, Map<String, dynamic> data) {
    final name = data['name'];
    if (name is! String) return null;
    final designation = data['designation'];
    return Employee(
      empId: id,
      name: name,
      designation: designation is String ? designation : '',
      active: data['active'] != false,
    );
  }

  /// Orders like a paper register: by Emp ID, with numbers in number order
  /// (so `EMP-9` comes before `EMP-10`).
  static int compareByEmpId(Employee a, Employee b) =>
      compareNatural(a.empId, b.empId);
}

final _chunk = RegExp(r'\d+|\D+');

/// Compares text with runs of digits compared as numbers.
int compareNatural(String a, String b) {
  final left = _chunk.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final right = _chunk.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < left.length && i < right.length; i++) {
    final x = left[i];
    final y = right[i];
    final xn = int.tryParse(x);
    final yn = int.tryParse(y);
    final order = xn != null && yn != null ? xn.compareTo(yn) : x.compareTo(y);
    if (order != 0) return order;
  }
  final byLength = left.length.compareTo(right.length);
  return byLength != 0 ? byLength : a.compareTo(b);
}

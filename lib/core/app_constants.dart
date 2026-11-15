/// App-wide text that isn't tied to a particular firm.
///
/// The app is built to serve many firms eventually, so the firm's own name
/// comes from the database (`companies` collection) after login, not from here.
abstract final class AppConstants {
  static const appName = 'Daily Attendance';
  static const tagline = 'Attendance made simple';
}

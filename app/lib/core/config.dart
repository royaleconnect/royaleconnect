/// Royale Connect — project configuration.
/// These two values are the school's live Supabase project. They are safe to ship inside the app:
/// everything a parent can see is decided by the row-level rules in the database, not by this key.
class AppConfig {
  static const supabaseUrl = 'https://upgvxhsxmdihmfmzknlq.supabase.co';
  static const supabaseAnonKey = 'sb_publishable_8mtHFfZ9Fk3p1YdG6gwydw_IXlULRxR';

  static const functionsUrl = '$supabaseUrl/functions/v1';

  static const schoolName = 'Royale Concorde International School';
  static const schoolShort = 'RCIS';
  /// The number the 'Call office' buttons dial.
  static const officePhone = '08025435454';
  /// How the school's numbers are written everywhere (screens, receipts, report cards, ID cards, certificates).
  static const officePhones = 'Ph: 080-25435454/55 · Mob: 9535216115';
  static const officePhonesShort = '080-25435454/55 · 9535216115';
  static const appName = 'Royale Connect';
  /// Public web address of the app (QR codes on receipts and report cards point here). Change when app.rcis.in is ready.
  static const webUrl = 'https://royaleconnect.github.io/royaleconnect';
  static const academicYearLabel = '2026-27';
  static const version = '0.1.0';
}

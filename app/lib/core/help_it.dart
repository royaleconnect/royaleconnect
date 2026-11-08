import 'help_content.dart';

/// IT handbook — help answers only IT and the Principal see (Help → "IT handbook").
/// Kept in its own list so the help page can add it only for them.

const itHandbookTopic = HelpTopic('IT handbook', '🛠️');

const itHandbookHelp = <HelpItem>[
  HelpItem('it-staff-add', 'IT handbook', 'How do I add a new staff member?', [
    'Open School setup → Staff → Add staff.',
    'Type the name, the school email (name@rcis.in), the phone and tick their roles (Teacher, Class teacher, Office…). Save.',
    'A one-time password slip appears. Print it or copy it and give it to them in person. They set their own password at first sign-in.',
    'To give them classes: School setup → Classes & fees → tap the class → choose the class teacher and subject teachers.',
  ], keywords: 'staff add new teacher join email role account login', route: '/staff/users', button: 'Open Staff'),
  HelpItem('it-staff-inactive', 'IT handbook', 'A teacher is leaving or going on long leave', [
    'Open School setup → Staff → tap the name → Make inactive.',
    'The app shows the classes and subjects they have. Choose who takes each one (or one teacher for all).',
    'Tap Make inactive. They are signed out; everything they wrote stays. Families see the new teacher at once.',
    'Coming back? Staff → Show inactive → tap the name → Make active again, then give their classes back.',
  ], keywords: 'staff inactive leaving resign handover long leave maternity deactivate active again', route: '/staff/users', button: 'Open Staff'),
  HelpItem('it-password', 'IT handbook', 'How do I give a new password slip?', [
    'Family: Students → find the student → Sign-in → New password slip. Print it and give it to the parent. The old password stops working.',
    'Staff: School setup → Staff → tap the name → Give a new one-time password.',
    'Lost phone? On the student’s page tap “Sign out all phones” first, then give a new slip.',
    'Each slip is the only copy and is recorded in the activity list.',
  ], keywords: 'password slip reset forgot new password locked sign in login parent staff', route: '/staff/students', button: 'Open Students'),
  HelpItem('it-sections', 'IT handbook', 'How do I switch a section of the app on or off?', [
    'Open School setup → Settings → Sections on / off.',
    'Switch off what the school does not use yet (for example Bus or Student Council), then Save.',
    'Families stop seeing it at once. Nothing is deleted — switch it on again any time.',
  ], keywords: 'sections on off feature switch hide show turn off menu', route: '/staff/settings', button: 'Open Settings'),
  HelpItem('it-bin', 'IT handbook', 'Something was deleted by mistake', [
    'Open School setup → Bin. Everything deleted in the last 30 days is there: notices, diary notes, calendar items, photos…',
    'Tap “Bring back” next to it. It returns exactly as it was.',
    'Only IT and the Principal can bring things back after 30 minutes. After 30 days items are removed for good.',
  ], keywords: 'bin deleted undo restore bring back recycle trash mistake removed', route: '/staff/bin', button: 'Open Bin'),
  HelpItem('it-branches', 'IT handbook', 'How do I start a new branch?', [
    'Open School setup → Settings → Branches.',
    'Fill in the branch details (name, address, phone, receipt start letters) and set it to Running.',
    'Then load its students and staff with Import from Excel. Each branch can have its own Sections on / off.',
  ], keywords: 'branch new branch campus chamarajpet chelekere pu college', route: '/staff/settings', button: 'Open Settings'),
  HelpItem('it-yearend', 'IT handbook', 'Year-end: what do I do, and when?', [
    'From 15 February a “Getting ready for the new year” card shows on your first page. Tap it for the checklist.',
    'By 1 March: new sections for next year, a class teacher for each, next year’s fee plan and calendar. The first move-up (VIII, IX, XI) happens by itself on 1 March.',
    'By 15 May: subject teachers set, the second move-up (happens by itself), X and XII leavers, certificates for everyone who left, board toppers after the results, final report cards, and a year-end backup.',
    'Most items tick themselves when the app can see they are done. Tick the others by hand. The card goes away when all is done, or after 30 June.',
  ], keywords: 'year end new year checklist move up promotion march may sections fee plan toppers leavers', route: '/staff/year-end', button: 'Open the checklist'),
  HelpItem('it-import', 'IT handbook', 'How do I bring in lists from Excel (or MCB)?', [
    'Open School setup → Classes & fees → Import from Excel.',
    'Choose what you are bringing in (students, staff, fees, bus…) and pick the file. Columns are matched for you — check them.',
    'The app lists any problems first. Nothing is saved until you tap Import.',
    'New people get password slips at the end. Print them in one go.',
  ], keywords: 'import excel xlsx csv upload mcb myclassboard bulk students staff fees list sheet', route: '/staff/setup', button: 'Open School setup'),
  HelpItem('it-down', 'IT handbook', 'What do I do if the app is down?', [
    'First check your own internet: open any other website.',
    'Look at the health dot at the top of your first page. Tap it to see what is not working.',
    'An email comes to the IT address when the website or database stops answering (checked every 30 minutes).',
    'Open status.supabase.com (the database company) — if they show a problem, it will come back by itself; tell the office to reassure parents.',
    'Still down after 30 minutes? Send a notice once it is back, and contact the app support person with the time it stopped.',
  ], keywords: 'down not working offline error outage cannot open blank loading slow server database'),
  HelpItem('it-backups', 'IT handbook', 'Where are the backups?', [
    'Every night at 3 am a full backup is made and kept for 30 days. It is locked with the school’s backup phrase.',
    'To download one: open github.com/royaleconnect/royaleconnect → Actions → Ops → a night run → Artifacts.',
    'Keep the backup phrase written down safely with the school. Without it a backup cannot be opened.',
    'At year end, download one backup and keep it on the school’s own computer or drive.',
  ], keywords: 'backup restore download data safe copy github ops artifact passphrase'),
  HelpItem('it-health', 'IT handbook', 'Where is the health dot, and what does it mean?', [
    'It is the small dot marked “Health” at the top of your first page (the whole-school dashboard).',
    'Green: all is well. Amber: something to look at (for example a night job did not run). Red: something is not working (for example phone notifications are stuck).',
    'Tap it to see each check and what to do. It checks again every 2 minutes.',
  ], keywords: 'health dot green amber red status system check notifications jobs', route: '/staff', button: 'Open my first page'),
];

/// Help answers. Written in short, plain sentences so every parent, student and teacher can follow them.
/// To add or change an answer, edit this list — nothing else is needed.

class HelpItem {
  final String id, topic, question;
  final List<String> steps;
  final String keywords;      // extra words people may type
  final String? route;        // screen the button opens
  final String? button;
  final bool popular;
  const HelpItem(this.id, this.topic, this.question, this.steps, {this.keywords = '', this.route, this.button, this.popular = false});

  bool matches(String q) {
    final words = q.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 1);
    final text = '$topic $question ${steps.join(' ')} $keywords'.toLowerCase();
    // each typed word must start a word in the answer (so “bus” does not find “syllabus”)
    return words.every((w) => RegExp('(^|[^a-z0-9])${RegExp.escape(w)}').hasMatch(text));
  }
}

class HelpTopic {
  final String name, icon;
  const HelpTopic(this.name, this.icon);
}

// ------------------------------------------------------------------ parents & students
const familyTopics = [
  HelpTopic('Fees', '💳'), HelpTopic('Bus', '🚌'), HelpTopic('Diary', '📒'), HelpTopic('Notices', '📢'), HelpTopic('Report cards', '📄'),
  HelpTopic('Sign-in', '🔑'), HelpTopic('Notifications', '🔔'), HelpTopic('Children', '👨‍👩‍👧'), HelpTopic('School', '🏫'),
];

const familyHelp = <HelpItem>[
  // Fees
  HelpItem('f-pay', 'Fees', 'How do I pay the fees online?', [
    'Tap Fees at the bottom of the screen.',
    'Tap the red Pay button. It shows how much is due now.',
    'Choose UPI, card or net banking and finish the payment.',
    'Your receipt appears at once. It is also sent as a notification.',
  ], keywords: 'payment pay online upi gpay phonepe card netbanking amount due instalment', route: '/fees', button: 'Open Fees', popular: true),
  HelpItem('f-receipt', 'Fees', 'Where is my fee receipt?', [
    'Tap Fees at the bottom of the screen.',
    'Tap “payments made · receipts”.',
    'Tap a payment to see the receipt. Use Print or Share to save it as a PDF.',
  ], keywords: 'receipt bill proof download pdf print share paid', route: '/receipts', button: 'Open receipts', popular: true),
  HelpItem('f-due', 'Fees', 'How do I see what is still to be paid?', [
    'Tap Fees at the bottom of the screen.',
    'You see each fee, its due date and whether it is paid.',
    'Fees shown in red are overdue.',
  ], keywords: 'balance pending due date overdue outstanding term', route: '/fees', button: 'Open Fees'),
  HelpItem('f-failed', 'Fees', 'Money was taken but the fee still shows unpaid', [
    'Please wait 10 minutes. Sometimes the bank takes a little time to confirm.',
    'Pull down on the Fees screen to refresh it.',
    'If it still shows unpaid, do not pay again. Call the school office with the date and amount — they will check it.',
  ], keywords: 'failed deducted debited pending stuck problem error double paid twice'),
  HelpItem('f-cash', 'Fees', 'Can I pay at the school office instead?', [
    'Yes. You can pay at the school office as before.',
    'The office enters it, and the payment and receipt appear in the app.',
  ], keywords: 'cash cheque office counter offline'),
  // Bus
  HelpItem('b-map', 'Bus', 'Where can I see the school bus?', [
    'Tap Bus at the bottom of the screen.',
    'When a trip is running, the green 🚌 moves on the map. Your stop is the red house.',
    'The card at the bottom shows how many stops and minutes away the bus is.',
  ], keywords: 'live location track tracking map gps where is the bus van', route: '/bus', button: 'Open the live bus map', popular: true),
  HelpItem('b-alerts', 'Bus', 'Why didn’t I get the “bus is 2 stops away” alert?', [
    'Open Bus → Alerts and check that the alerts are switched on.',
    'Check that notifications for Royale Connect are allowed in your phone settings.',
    'If the bus was in a low-network area, the alert may come a little late.',
  ], keywords: 'notification alert two stops 10 minutes not coming late', route: '/bus', button: 'Open Bus'),
  HelpItem('b-call', 'Bus', 'How do I call the driver or the bus assistant?', [
    'Tap Bus at the bottom of the screen.',
    'On the map card, tap Driver or Bus assistant to call.',
  ], keywords: 'phone number driver conductor attendant contact', route: '/bus', button: 'Open Bus'),
  HelpItem('b-stop', 'Bus', 'How do I change my child’s bus stop?', [
    'Please tell the school transport office or the school office.',
    'Once they change it, the new stop shows in the app.',
  ], keywords: 'change stop pickup point address moved shifted'),
  HelpItem('b-none', 'Bus', 'I can’t see the Bus button', [
    'The Bus button appears only for children who use the school bus.',
    'If your child uses the school bus, please tell the school office so they can add it.',
  ], keywords: 'missing no bus tab not showing'),
  // Diary & studies
  HelpItem('d-home', 'Diary', 'Where do I see homework?', [
    'Tap Diary at the bottom of the screen.',
    'Each day shows the homework, things to bring and tests, subject by subject.',
    'Use the arrows at the top to see other days.',
  ], keywords: 'homework classwork assignment things to bring test project', route: '/diary', button: 'Open the diary', popular: true),
  HelpItem('d-exam', 'Diary', 'Where are the exam dates and portions?', [
    'On Home, tap Exams.',
    'Each exam shows the date and the portions for each subject.',
  ], keywords: 'exam test portion syllabus timetable date periodic term', route: '/exams', button: 'Open exams'),
  HelpItem('d-tt', 'Diary', 'Where is the class timetable?', [
    'On Home, tap Timetable. It shows each day’s periods.',
  ], keywords: 'timetable periods schedule', route: '/timetable', button: 'Open timetable'),
  HelpItem('d-ws', 'Diary', 'Where are the worksheets?', [
    'On Home, tap Worksheets.',
    'Tap a worksheet to open or download it.',
  ], keywords: 'worksheet practice download pdf', route: '/worksheets', button: 'Open worksheets'),
  // Notices
  HelpItem('n-notice', 'Notices', 'Where do I see school notices?', [
    'Tap Notices at the bottom of the screen.',
    'New notices have a red dot. Tap one to read it fully.',
  ], keywords: 'circular announcement notice news message from school', route: '/announcements', button: 'Open notices'),
  HelpItem('n-cal', 'Notices', 'How do I see holidays and school events?', [
    'On Home, tap Calendar.',
    'Holidays are in red, events in blue and exams in yellow.',
  ], keywords: 'holiday leave event calendar ptm function', route: '/calendar', button: 'Open calendar'),
  // Report cards
  HelpItem('r-card', 'Report cards', 'Where is my child’s report card?', [
    'Tap Reports at the bottom of the screen.',
    'Tap the term to open the report card. Use Print or Share to save it.',
    'Report cards appear only after the school publishes them.',
  ], keywords: 'result marks grades report card progress', route: '/reports', button: 'Open report cards'),
  // Sign-in
  HelpItem('s-forgot', 'Sign-in', 'I forgot my password', [
    'Please ask the class teacher or the school office.',
    'They will give you a new password slip.',
    'Sign in with it, then choose your own new password.',
  ], keywords: 'forgot password reset locked cannot login sign in', popular: true),
  HelpItem('s-change', 'Sign-in', 'How do I change my password?', [
    'On Home, tap ⚙ (Settings) at the top.',
    'Tap Change password and type the new one twice.',
  ], keywords: 'change password new password', route: '/settings', button: 'Open settings'),
  HelpItem('s-family', 'Sign-in', 'Can both parents use the app?', [
    'Yes. Both parents (and the student) use the same admission number and password.',
    'Sign in on each phone once. Everyone gets the same notices and alerts.',
  ], keywords: 'mother father both parents two phones another phone same login'),
  HelpItem('s-out', 'Sign-in', 'How do I sign out?', [
    'On Home, tap ⚙ (Settings) at the top.',
    'Tap “Sign out of this phone” at the bottom.',
  ], keywords: 'logout log out sign out', route: '/settings', button: 'Open settings'),
  // Children
  HelpItem('c-add', 'Children', 'How do I add my other child?', [
    'On Home, tap ⚙ (Settings) at the top → Students on this phone.',
    'Tap “Add a sibling”.',
    'Type that child’s admission number and password once.',
    'Now tap the child’s name at the top of Home any time to switch between children.',
  ], keywords: 'sibling brother sister second child two children add switch', route: '/students', button: 'Add or switch child', popular: true),
  // Notifications
  HelpItem('o-none', 'Notifications', 'I’m not getting notifications', [
    'Open your phone Settings → Apps → Royale Connect → Notifications, and switch them on.',
    'On some phones (Xiaomi, Vivo, Oppo, Realme) also set Battery → “No restrictions” for Royale Connect.',
    'Open the app once after that. Notifications will start coming.',
  ], keywords: 'notification alert not coming no sound push message', popular: true),
  HelpItem('o-night', 'Notifications', 'Why do some messages come in the morning?', [
    'The school keeps quiet hours from 12 am to 5 am, so your sleep is not disturbed.',
    'Messages sent at night come at 5 am. Urgent alerts and bus alerts always come at once.',
  ], keywords: 'night quiet hours late morning delay'),
  // School
  HelpItem('m-teacher', 'School', 'How do I message the class teacher?', [
    'On Home, tap the 💬 speech bubble at the top.',
    'Choose the teacher and type your message. The teacher replies in the app.',
  ], keywords: 'message chat teacher contact talk ask', route: '/messages', button: 'Open messages'),
  HelpItem('m-leave', 'School', 'How do I apply for leave for my child?', [
    'On Home, tap Leave.',
    'Tap Apply, choose the dates and write the reason.',
    'The class teacher sees it at once. You get a notification when it is approved.',
  ], keywords: 'leave absent sick holiday not coming', route: '/leave', button: 'Open leave'),
  HelpItem('m-photos', 'School', 'Where are class photos?', [
    'On Home, tap Gallery. Photos are shared only with families of that class.',
  ], keywords: 'photo picture gallery moments album event', route: '/gallery', button: 'Open gallery'),
  HelpItem('m-fb', 'School', 'How do I give feedback or a suggestion to the school?', [
    'On Home, tap ⚙ (Settings) → Feedback to the school.',
    'Write your message. The school office will reply.',
  ], keywords: 'feedback complaint suggestion problem', route: '/feedback', button: 'Open feedback'),
  HelpItem('m-toppers', 'School', 'Where are the Board Toppers and the Hall of Fame?', [
    'On Home, tap Toppers.',
    'Choose Class X or Class XII and a year to see the top 3 and the subject centums.',
    'Tap Hall of Fame to see former students and where they are today.',
  ], keywords: 'toppers topper board results rank centum 100 hall of fame alumni old students', route: '/toppers', button: 'Open Toppers'),
  HelpItem('m-newclass', 'School', 'It says “section to be announced”', [
    'Your child has moved up to the new class. The school is now making the new sections.',
    'When the school publishes them you get a notification with the section and class teacher.',
  ], keywords: 'section to be announced new class next year moved up promotion tba'),
];

// ------------------------------------------------------------------ teachers & office
const staffTopics = [
  HelpTopic('Getting started', '🔑'), HelpTopic('Class', '📒'), HelpTopic('Marks', '📝'), HelpTopic('Notices', '📢'),
  HelpTopic('Parents', '💬'), HelpTopic('Office', '🏫'), HelpTopic('Setup', '⚙️'),
];

const staffHelp = <HelpItem>[
  HelpItem('t-signin', 'Getting started', 'How do I sign in the first time?', [
    'On the sign-in page, tap “School staff? Sign in here”.',
    'Type your school email (for example name@rcis.in) and the password you were given.',
    'Choose your own new password. Use it from now on.',
  ], keywords: 'login sign in first time password email staff1', popular: true),
  HelpItem('t-forgot', 'Getting started', 'I forgot my password', [
    'Ask the IT admin or the Principal.',
    'They will give you a one-time password. Sign in with it and choose a new one.',
  ], keywords: 'forgot reset password locked'),
  HelpItem('t-menu', 'Getting started', 'Where is everything?', [
    'Start on Today: it shows what is waiting for you, with the button to do it.',
    'On a laptop, the menu is on the left in groups: Today · My class · Exams & reports · Students · School · Me.',
    'On a phone, the 4 most used pages are at the bottom. Tap ☰ (top right) for the full menu.',
    'You only see the pages for your role. IT can change this in School settings.',
  ], keywords: 'menu find page navigation missing'),
  HelpItem('t-diary', 'Class', 'How do I post homework in the diary?', [
    'Open Class diary.',
    'Choose the class and subject.',
    'Choose Homework / To bring / Test, type it and tap “Post entry”. Parents get it at once.',
  ], keywords: 'homework diary classwork post add assignment', route: '/staff/diary', button: 'Open Class diary', popular: true),
  HelpItem('t-leave', 'Class', 'How do I approve a leave request?', [
    'Open Leave requests.',
    'Tap Approve or Decline. The parent gets a notification.',
  ], keywords: 'leave absent approve decline', route: '/staff/leave', button: 'Open Leave requests'),
  HelpItem('t-moments', 'Class', 'How do I share class photos?', [
    'Open Class moments → choose the class → tap “Add photos” and write a caption.',
    'Only children whose parents allowed photos should be in them.',
  ], keywords: 'photo picture moments gallery upload', route: '/staff/moments', button: 'Open Class moments'),
  HelpItem('t-star', 'Class', 'How do I choose the Star of the month?', [
    'Open Star of the month → choose the class and the student → write why.',
  ], keywords: 'star month award', route: '/staff/star', button: 'Open Star of the month'),
  HelpItem('t-marks', 'Marks', 'How do I enter marks?', [
    'Open Marks entry.',
    'Choose the exam, class and subject.',
    'Type each student’s marks and tap “Save marks”. You can change them later until the report card is published.',
  ], keywords: 'marks enter exam score result', route: '/staff/marks', button: 'Open Marks entry', popular: true),
  HelpItem('t-report', 'Marks', 'How do I make report cards?', [
    'Open Report cards (class teachers).',
    'Choose your class and term. Fill attendance, height, weight, co-scholastic grades and remarks.',
    'Tap Preview PDF to check one, then Publish. Parents see it at once.',
  ], keywords: 'report card remarks publish term attendance co-scholastic', route: '/staff/reports', button: 'Open Report cards'),
  HelpItem('t-exams', 'Marks', 'How do I add exam dates and portions?', [
    'Open Exams & portions → New exam → choose the grade and subjects.',
    'Add dates and portions for each subject, then Publish.',
  ], keywords: 'exam portion syllabus date schedule', route: '/staff/exams', button: 'Open Exams & portions'),
  HelpItem('t-notice', 'Notices', 'How do I send a notice to parents?', [
    'Open Announcements → New announcement.',
    'Choose who gets it: whole school, some grades or some classes.',
    'Type the notice, add a PDF or photo if needed, and send. You can also schedule it for later.',
  ], keywords: 'announcement circular notice send parents all', route: '/staff/announcements', button: 'Open Announcements', popular: true),
  HelpItem('t-seen', 'Notices', 'How do I know which parents read a notice?', [
    'Open Announcements. Each notice shows how many families read it.',
    'Tap Remind to send it again only to those who have not read it.',
  ], keywords: 'read seen remind not read', route: '/staff/announcements', button: 'Open Announcements'),
  HelpItem('t-msg', 'Parents', 'How do I reply to a parent’s message?', [
    'Open Messages. New messages show a red number.',
    'Tap the message, type your reply and send.',
    'Messages sent between 12 am and 5 am reach the parent at 5 am.',
  ], keywords: 'message chat reply parent', route: '/staff/messages', button: 'Open Messages', popular: true),
  HelpItem('t-slip', 'Parents', 'A parent forgot their password', [
    'Open Students → find the student.',
    'Teachers: tap ⋮ → “Reset password (print slip)”. Office: open the student → “New password slip”.',
    'Give the slip to the parent.',
  ], keywords: 'parent forgot password reset slip', route: '/staff/students', button: 'Open Students'),
  HelpItem('o-fees', 'Office', 'How do I check a student’s fees?', [
    'Open Fees desk and search the student’s name or admission number.',
    'You see every fee, what is paid and what is due. Tap a payment to print its receipt.',
  ], keywords: 'fees due paid receipt balance', route: '/staff/fees', button: 'Open Fees desk'),
  HelpItem('o-cal', 'Office', 'How do I add a holiday or event?', [
    'Open School calendar → tap a date → choose Holiday, Event, Exam or Parents’ meeting.',
    'Keep “Tell families now” on to send a notification.',
  ], keywords: 'holiday event calendar ptm', route: '/staff/calendar', button: 'Open School calendar'),
  HelpItem('o-bus', 'Office', 'How do drivers sign in?', [
    'Open Transport. Each route has a Driver and a Bus assistant login (for example dr7 and as7).',
    'They sign in at “School staff? Sign in here” with that ID and the common bus password.',
  ], keywords: 'driver bus assistant conductor login dr as transport', route: '/staff/transport', button: 'Open Transport'),
  HelpItem('s-admit', 'Setup', 'How do I add a new student?', [
    'Open Students → New admission.',
    'Fill in the details and at least one parent mobile, then tap Admit student.',
    'Print the password slip that appears and give it to the parents.',
    'A student who studied here before (for example Grade X → re-admission in XI) is linked to the old admission by itself.',
  ], keywords: 'new admission add student join readmission', route: '/staff/students', button: 'Open Students', popular: true),
  HelpItem('s-left', 'Setup', 'A student has left the school', [
    'Open Students → find the student → Edit details.',
    'Switch off “Studying here” and add the TC date. Their old receipts and report cards are kept for ever under Past students.',
  ], keywords: 'left tc transfer certificate remove student', route: '/staff/students', button: 'Open Students'),
  HelpItem('s-docs', 'Setup', 'How do I keep a TC, marksheet or certificate?', [
    'Open Students → search the name or admission number (choose Past students for old students).',
    'Open the student → Documents → Upload. Choose what it is (TC, Marksheet, Conduct, Bonafide, Birth certificate) and pick the PDF or photo.',
    'Later, tap the document to print it or share it. Every upload, print and share is recorded.',
  ], keywords: 'tc transfer certificate marksheet conduct bonafide study birth document upload print share alumni old student', route: '/staff/students', button: 'Open Students', popular: true),
  HelpItem('s-readmit', 'Setup', 'The app asks “Same child?”', [
    'When a new admission has the same date of birth and name as an earlier student, the app links them so the child has one history.',
    'If it is not sure, Students shows “re-admissions to check”. Tap Check now and choose “Same child — link” or “Not the same”.',
  ], keywords: 'readmission re-admission link same child grade 11 xi new admission number', route: '/staff/students', button: 'Open Students'),
  HelpItem('s-sections', 'Setup', 'How do I make next year’s sections?', [
    'Open New sections (IT and the Principal).',
    'Tap a grade. Step 1: add the sections and choose each class teacher.',
    'Step 2: upload the school’s Excel list (Admission number + Section) or choose the section for each student.',
    'Step 3: tap “Publish to families”. Until then families see “section to be announced”.',
  ], keywords: 'new sections next year shuffle class teacher promote move up placement', route: '/staff/sections', button: 'Open New sections'),
  HelpItem('s-moveup', 'Setup', 'When do classes move up?', [
    '1 March: Grades VIII, IX and XI move up (XI → XII keep the same sections).',
    '15 May: every other class moves up and Grades X and XII become past students.',
    'It happens by itself. IT and the Principal get a reminder a week before. IT can change the dates in School settings → Year dates.',
  ], keywords: 'move up promotion new year 1 march 15 may past students year end'),
  HelpItem('s-toppers', 'Setup', 'How do I add Board Toppers or Hall of Fame?', [
    'Open Toppers & Hall of Fame.',
    'Choose Class X or XII, add the year, then the top 3 (with photos) and the subject centums.',
    'For the Hall of Fame, tap “Add a person”.',
  ], keywords: 'toppers board results centum hall of fame alumni photo', route: '/staff/toppers', button: 'Open Toppers'),
  HelpItem('s-settings', 'Setup', 'How do I switch a feature off or change who sees a page?', [
    'IT: open School settings.',
    '“Who can use what” — tick the roles that see each page. “Features” — switch features on or off for families.',
  ], keywords: 'settings permission access role feature switch off hide page', route: '/staff/settings', button: 'Open School settings'),
  HelpItem('s-import', 'Setup', 'How do I import a list from Excel?', [
    'Open Classes & fees → Import from Excel.',
    'Choose what you are importing and upload the file. Columns are matched for you.',
    'Check the list of problems (nothing is saved yet), then tap Import.',
  ], keywords: 'excel import upload sheet list bulk mcb', route: '/staff/setup', button: 'Open Classes & fees'),
  HelpItem('s-classes', 'Setup', 'How do I change a class teacher or subject teacher?', [
    'Open Classes & fees → Classes → tap the class.',
    'Choose the class teacher and the teacher for each subject, then Save.',
  ], keywords: 'class teacher subject teacher assign section', route: '/staff/setup', button: 'Open Classes & fees'),
];

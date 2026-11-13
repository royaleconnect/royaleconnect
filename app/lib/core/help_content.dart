/// Help answers. Written in short, plain sentences so every parent, student and teacher can follow them.
/// To add or change an answer, edit this list — nothing else is needed.

class HelpItem {
  final String id, topic, question;
  final List<String> steps;
  final String keywords;      // extra words people may type
  final String? route;        // screen the button opens
  final String? button;
  final bool popular;
  /// Staff help: the page a person must be able to open to see this answer (when it is not the same as [route]).
  final String? needs;
  const HelpItem(this.id, this.topic, this.question, this.steps, {this.keywords = '', this.route, this.button, this.popular = false, this.needs});

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
  HelpTopic('Fees', '💳'), HelpTopic('Transport', '🚌'), HelpTopic('Diary', '📒'), HelpTopic('Notices', '📢'), HelpTopic('Report cards', '📄'),
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
  HelpItem('b-map', 'Transport', 'Where can I see the school bus?', [
    'Tap Transport at the bottom of the screen.',
    'When a trip is running, the green 🚌 moves on the map. Your stop is the red house.',
    'The card at the bottom shows how many stops and minutes away the bus is.',
  ], keywords: 'live location track tracking map gps where is the bus van', route: '/bus', button: 'Open the live bus map', popular: true),
  HelpItem('b-alerts', 'Transport', 'Why didn’t I get the “bus is 2 stops away” alert?', [
    'Open Bus → Alerts and check that the alerts are switched on.',
    'Check that notifications for Royale Connect are allowed in your phone settings.',
    'If the bus was in a low-network area, the alert may come a little late.',
  ], keywords: 'notification alert two stops 10 minutes not coming late', route: '/bus', button: 'Open Bus'),
  HelpItem('b-call', 'Transport', 'How do I call the driver or the bus assistant?', [
    'Tap Transport at the bottom of the screen.',
    'On the map card, tap Driver or Bus assistant to call.',
  ], keywords: 'phone number driver conductor attendant contact', route: '/bus', button: 'Open Bus'),
  HelpItem('b-stop', 'Transport', 'How do I change my child’s bus stop?', [
    'Please tell the school transport office or the school office.',
    'Once they change it, the new stop shows in the app.',
  ], keywords: 'change stop pickup point address moved shifted'),
  HelpItem('b-none', 'Transport', 'I can’t see the Bus button', [
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
    'On Home, tap Calendar, then the Exams tab.',
    'Each exam shows the date and the portions for each subject.',
  ], keywords: 'exam test portion syllabus timetable date periodic term', route: '/exams', button: 'Open exams'),
  HelpItem('d-tt', 'Diary', 'Where is the class timetable?', [
    'On Home, tap Calendar, then the Timetable tab. It shows each day’s periods with times.',
  ], keywords: 'timetable periods schedule', route: '/timetable', button: 'Open timetable'),
  HelpItem('d-att', 'Diary', 'Where can I see attendance?', [
    'On Home, tap Attendance. You see the streak (days present in a row), this month day by day, and the year so far.',
    'The Leave tab is where you ask for leave.',
  ], keywords: 'attendance absent present streak leave', route: '/attendance', button: 'Open attendance'),
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
    'Tap Change password, type your current password, then the new one twice.',
  ], keywords: 'change password new password', route: '/settings', button: 'Open settings'),
  HelpItem('s-privacy', 'Sign-in', 'Who can see my child’s information?', ['On Home, tap ⚙ (Settings) at the top.', 'Tap Privacy policy.'], keywords: 'privacy data information who sees policy', route: '/privacy', button: 'Open privacy policy'),
  HelpItem('s-delete', 'Sign-in', 'How do I delete our account?', ['On Home, tap ⚙ (Settings) at the top.', 'Tap Request account deletion and send.', 'The school office will contact you.'], keywords: 'delete account remove close data', route: '/settings', button: 'Open settings'),
  HelpItem('f-today', 'Home', 'What is the “Your day” card?', ['The top line says if today is a school day or a holiday, with the bus pickup time and any event.', 'Needs you shows only what needs you: a fee to pay (with a Pay button), homework for the next school day, and new notices. When it says “All done for today ✨”, there is nothing to do.', 'My list is beside it: tick an item right there, or tap See all.'], keywords: 'your day today needs you card home pay homework notice holiday school day my list', route: '/'),
  HelpItem('bus_pin', 'Transport', 'How do I change my bus pickup point?', ['Open Bus.', 'Tap Change on “Pickup point”.', 'Choose “Use my location now” or “Move the pin on the map”.'], keywords: 'pin pickup location bus point', route: '/bus', button: 'Open Bus'),
  HelpItem('bus_pins_staff', 'Transport', 'How do I check the children’s home pins?', ['Open Check pins.', 'Choose the bus.', 'Press “Place pins from addresses” once.', 'Amber = please check: tap the child, then tap the right spot on the map.'], keywords: 'pins geocode map address home', route: '/staff/bus-pins', button: 'Open Check pins'),
  HelpItem('bus_end_trip', 'Transport', 'A driver forgot to end the trip', ['Open Transport.', 'Under “Buses running now” press End trip.', 'Trips also end by themselves 15 minutes after reaching school, or after 3 hours.'], keywords: 'end trip running forgot bus', route: '/staff/transport', button: 'Open Transport'),
  HelpItem('class-logins', 'Students', 'A parent forgot the password — what do I do?', ['Open Class logins.', 'Tap Reset next to the child.', 'Read the new password to the parent. They choose their own at the first sign-in.'], keywords: 'password login forgot slip reset class', route: '/staff/class-logins', button: 'Open Class logins'),
  HelpItem('staff-first-pw', 'Office', 'How do staff get their first password?', ['IT: open Approvals and tap “Make and print slips”.', 'Give each person their slip.', 'Everyone chooses their own password at the first sign-in.'], keywords: 'staff password slip first login new teacher', route: '/staff/approvals', button: 'Open Approvals'),
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
    'On Home, tap Attendance, then the Leave tab.',
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
    'On Home, tap Honours, then Toppers (or Hall of Fame).',
    'Choose Class X or Class XII and a year to see the top 3 and the subject centums.',
    'Tap Hall of Fame to see former students and where they are today.',
  ], keywords: 'toppers topper board results rank centum 100 hall of fame alumni old students', route: '/toppers', button: 'Open Toppers'),
  HelpItem('m-council', 'School', 'Where is the Student Council? How do I vote?', [
    'On Home, tap Honours, then Council to see this year’s council. Earlier years are the tabs at the top.',
    'When the elections open you get a notification and a red “Vote now” box appears there.',
    'Choose one candidate for each post, check your choices and tap “Submit my vote”. Your vote is secret and cannot be changed.',
  ], keywords: 'student council head boy head girl captain election vote voting candidates'),
  HelpItem('m-desk', 'School', 'What is “From the Principal’s Desk”?', [
    'Messages from our Principal — her welcome, and her notes about RoMUN, the RoAI Hackathon, Annual Day, Sports Day and other events.',
    'A new message opens full screen once, the next time you open the app. Tap Continue to go on.',
    'To read any of them again: Home → the “From the Principal’s Desk” card (or the menu → Principal’s Desk), then tap a message.',
  ], keywords: 'principal message welcome desk event romun hackathon annual day sports day', route: '/desk', button: "Open Principal's Desk"),
  HelpItem('m-sunday', 'School', 'What is the Sunday message?', [
    'Every Sunday at 6 pm you get one message about the week ahead: homework due, tests, holidays and any fee due.',
    'Nothing to do — it is a reminder so nothing is missed.',
  ], keywords: 'sunday summary week ahead weekly reminder notification'),
  HelpItem('m-newclass', 'School', 'It says “section to be announced”', [
    'Your child has moved up to the new class. The school is now making the new sections.',
    'When the school publishes them you get a notification with the section and class teacher.',
  ], keywords: 'section to be announced new class next year moved up promotion tba'),
  // ---- Release F
  HelpItem('d-mylist', 'Diary', 'What is “My list”?', ['Open Diary and tap My list.', 'Homework with a due date appears by itself. Tap + Add my own for anything else.', 'Tick when done. Ticked items go away the next day; late ones show in red.'], keywords: 'my list checklist homework tick todo', route: '/diary', button: 'Open diary'),
  HelpItem('f-houses', 'School', 'Where can I see the house points?', ['Open Honours → Houses. The four flags rise to this year’s points; the leader has a crown.', 'Your child’s house is shown under the flags.'], keywords: 'house points athena ares artemis apollo flag', route: '/houses', button: 'Open Houses'),
  HelpItem('f-thanks', 'School', 'How do I send a Teachers’ Day thank-you?', ['During Teachers’ Day week (2–8 September) tap “Say thank you to your teachers” on Home.', 'Tap a teacher, write a line or tap a ready line, then Send. One note per teacher each year.'], keywords: 'teachers day thank you note wall september', route: '/thanks', button: 'Open'),
  HelpItem('f-review', 'School', 'What is the Year in Review?', ['From 15 May to 30 June a card on Home plays a short story of your child’s year.', 'Tap the right side for next, the left side for back. On the last card tap Share with family.'], keywords: 'year in review story share may', route: '/year-review', button: 'Play'),
  HelpItem('forgot_password', 'Sign-in', 'I forgot the password', ['On the sign-in screen tap “Forgot password?”.', 'Type the admission number and the phone number registered with the school.', 'The class teacher gets your request and gives you a new password slip.'], keywords: 'forgot password reset new slip sign in'),
  HelpItem('f-idcard', 'Children', 'Where is the ID card?', ['Open Profile → ID card.', 'Tap the card to turn it over. Show it at the gate or on the bus.'], keywords: 'id card identity gate bus', route: '/idcard', button: 'Open ID card'),
  HelpItem('auto-dark', 'School', 'Why does the app turn dark in the evening?', ['The app uses its dark look from 6:15 pm to 6:15 am and the light look in the day, by itself.', 'To keep one look all the time: Settings → Appearance → Light or Dark.'], keywords: 'night dark theme light', route: '/settings', button: 'Open Settings'),
  HelpItem('offline', 'School', 'Can I use the app without internet?', ['The diary, notices, timetable, ID card and fees open from the copy saved last time.', 'A thin bar at the top shows when that copy was saved.', 'A message typed without internet goes by itself when the internet is back.'], keywords: 'offline no internet network'),
  HelpItem('f-tour', 'School', 'How do I see the app tour again?', ['Open Help (Profile → Help & feedback).', 'Tap “Take the tour again” at the top.'], keywords: 'tour guide intro walkthrough how to use app new'),
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
    'On a laptop, the menu is on the left in groups (for example Today · My class · School · Me). Each page has the same name as in the menu.',
    'On a phone, the 4 most used pages are at the bottom. Tap ☰ (top right) for the full menu.',
    'You only see the pages for your role. IT can change this in School settings.',
  ], keywords: 'menu find page navigation missing'),
  HelpItem('t-diary', 'Class', 'How do I post homework in the diary?', [
    'Open Diary.',
    'Choose the class and subject.',
    'Choose Homework / To bring / Test, type it and tap “Post entry”. Parents get it at once.',
  ], keywords: 'homework diary classwork post add assignment', route: '/staff/diary', button: 'Open Diary', popular: true),
  HelpItem('t-leave', 'Class', 'How do I approve a leave request?', [
    'Class teachers: Today shows “N leave requests” — tap it, or open Leave requests in the menu.',
    'Tap Approve or Decline. The family is told at once.',
  ], keywords: 'leave absent approve decline', route: '/staff/leave', button: 'Open Leave requests'),
  HelpItem('t-moments', 'Class', 'How do I share class photos?', [
    'Open Class photos → choose the class → tap “Add photos” and write a caption.',
    'Only children whose parents allowed photos should be in them.',
  ], keywords: 'photo picture moments gallery upload', route: '/staff/moments', button: 'Open Class photos'),
  HelpItem('t-star', 'Class', 'How do I choose the Star of the month?', [
    'Open Star of the month → choose the class and the student → write why.',
  ], keywords: 'star month award', route: '/staff/star', button: 'Open Star of the month'),
  HelpItem('t-marks', 'Marks', 'How do I enter marks?', [
    'Open Exams & marks → Marks entry. Choose the exam, the class and the subject (class teachers can choose “All subjects”).',
    'Type the marks and press Tab for the next box. They save by themselves — “✓ Saved” shows at the top. Type AB for absent.',
    'A box turns red when the number is above the maximum; it is not saved until you correct it.',
    'Subject teachers enter their own subjects. The class teacher can enter every subject of her class. IT and the office can enter any class.',
  ], keywords: 'marks enter exam score result internals written theory practical absent', route: '/staff/marks', button: 'Open Marks entry', popular: true),
  HelpItem('t-marks-out-of', 'Marks', 'What are the marks out of?', [
    'Periodic Test 1 and 2: out of 30 in every subject and every class.',
    'Half Yearly and Annual: Grade I – V out of 50 (written). Grade VI – X: Internals 20 + Written 80.',
    'Grade XI – XII: each subject’s own Theory + Practical — Physics, Chemistry, Biology, IP, Computer Science, PE, Psychology and Home Science 70 + 30; English and Maths 80 + 20; AI 50 + 50.',
    'Grade IX’s 3rd language is shown separately and not added to the total (CBSE). In VI – VIII it is part of the total (out of 600). Computers / AI in I – X are shown separately.',
  ], keywords: 'maximum out of 30 50 80 20 70 theory practical total 500 600 third language', route: '/staff/exams', button: 'Open Exams & marks'),
  HelpItem('t-marks-one', 'Marks', 'How do I change one student’s marks, grades or remarks?', [
    'Open Students → the student → Marks.',
    'Pick the exam at the top and tap “Enter / change marks”.',
    'Change the marks, the co-scholastic grades, height, weight, remark or participation — then tap Save.',
    'No reason is asked. The app keeps who changed what, in case of a question later.',
  ], keywords: 'change marks student correct remark height weight grade discipline', route: '/staff/students', button: 'Open Students'),
  HelpItem('t-exam-add', 'Marks', 'How do I add an exam (Pre-board, re-test …)?', [
    'Every class already gets PT 1, Half Yearly, PT 2 and Annual by itself (X and XII: Pre-board 1 and 2).',
    'For anything else: Exams & marks → Add exam → name it, choose “Term exam”, “Test” or your own maximum, pick the classes.',
    'Each class’s subjects come in by themselves. Tap a subject to set its date, portions and (office) its maximum.',
  ], keywords: 'add exam preboard pre-board test new exam dates portions', route: '/staff/exams', button: 'Open Exams & marks'),
  HelpItem('t-fee-remind', 'Office', 'How do I remind one family about overdue fees?', [
    'Open Students → the student → Fees.',
    'Tap “Send reminder”. You see the exact message the family gets before it goes.',
    'One reminder every 3 days per family. The date of the last one shows on the same page.',
  ], keywords: 'fee reminder overdue remind family late fee', route: '/staff/students', button: 'Open Students'),
  HelpItem('t-report', 'Marks', 'How do I make report cards?', [
    'Open Exams & marks → Report cards (class teachers).',
    'Choose your class and term. Fill attendance, height, weight, co-scholastic grades and remarks.',
    'Tap Preview PDF to check one, then Publish. Parents see it at once.',
  ], keywords: 'report card remarks publish term attendance co-scholastic', route: '/staff/reports', button: 'Open Report cards'),
  HelpItem('t-exams', 'Marks', 'How do I add exam dates and portions?', [
    'Open Exams & marks → New exam → choose the grade and subjects.',
    'Add dates and portions for each subject, then Publish.',
  ], keywords: 'exam portion syllabus date schedule', route: '/staff/exams', button: 'Open Exams & marks'),
  HelpItem('t-notice', 'Notices', 'How do I send a notice to parents?', [
    'Open Notices → New notice.',
    'Choose who gets it. Class teachers send to their own class; coordinators to their grades; the office to the whole school, grades, classes or bus families.',
    'Type the notice, add a PDF or photo if needed, and send. You can also schedule it for later.',
  ], keywords: 'announcement circular notice send parents all', route: '/staff/announcements', button: 'Open Notices', popular: true),
  HelpItem('t-seen', 'Notices', 'How do I know which parents read a notice?', [
    'Open Notices. Each notice shows how many families read it.',
    'Tap Remind to send it again only to those who have not read it.',
  ], keywords: 'read seen remind not read', route: '/staff/announcements', button: 'Open Notices'),
  HelpItem('t-msg', 'Parents', 'How do I reply to a parent’s message?', [
    'Open Messages. New messages show a red number.',
    'Tap the message, type your reply and send.',
    'Messages sent between 12 am and 5 am reach the parent at 5 am.',
  ], keywords: 'message chat reply parent', route: '/staff/messages', button: 'Open Messages', popular: true),
  HelpItem('t-slip', 'Parents', 'A parent forgot their password', [
    'When a parent asks for help from the sign-in page, it shows on Today for the class teacher (and in Approvals for the office).',
    'Or open Students → find the student. Class teacher: tap ⋮ → “Reset password (print slip)”. Office: open the student → “New password slip”.',
    'Give the slip to the parent.',
  ], keywords: 'parent forgot password reset slip', route: '/staff/students', button: 'Open Students'),
  HelpItem('o-fees', 'Office', 'How do I check a student’s fees?', [
    'Open Fees & receipts and search the student’s name or admission number.',
    'You see every fee, what is paid and what is due. Tap a payment to print its receipt.',
  ], keywords: 'fees due paid receipt balance', route: '/staff/fees', button: 'Open Fees & receipts'),
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
    'Open Students → find the student → tap “Student is leaving”.',
    'Choose the last day and the reason, upload the signed TC and conduct certificate, then Confirm.',
    'The student moves to Past students; fees, marks and documents are kept for ever. Students → Past students shows anyone still waiting for a certificate.',
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
  ], keywords: 'move up promotion new year 1 march 15 may past students year end', needs: '/staff/sections'),
  HelpItem('s-toppers', 'Setup', 'How do I add Board Toppers or Hall of Fame?', [
    'Open Honours → Add or change (office, IT, Principal).',
    'Choose Class X or XII, add the year, then the top 3 (with photos) and the subject centums.',
    'For the Hall of Fame, tap “Add a person”.',
  ], keywords: 'toppers board results centum hall of fame alumni photo', route: '/staff/toppers/edit', button: 'Open Honours'),
  HelpItem('s-report', 'Office', 'How do I get the monthly report?', [
    'Principal / IT: on Today (the whole-school page), tap “Monthly report”.',
    'Choose the month, type the month’s highlights if you like, and tap “Make the PDF” — then Print or Share.',
  ], keywords: 'monthly report pdf management meeting summary principal', needs: '/staff/week'),
  HelpItem('s-desk', 'Setup', 'How does the Principal send a message to everyone?', [
    'IT / Principal: Principal’s Desk → New message. Write a title and the message (leave an empty line between paragraphs).',
    'The design is chosen from the title by itself: Annual Day (stage curtains), Sports Day (running track), Hackathon / RoAI (glowing circuits), MUN (globe); anything else gets the royal gold design.',
    'Optional: a picture or poster, and a link (e.g. a registration form) with its button text. Tap Preview to see it exactly as everyone will.',
    'Send: everyone gets a notification, and it opens full screen once on their next opening. Remove it from the list any time (⋮ → Remove).',
    'The welcome messages (one for families, one for staff), the Principal’s name and her photo are changed on the same page.',
  ], keywords: 'principal message desk welcome event full screen photo signature name', route: '/staff/desk', button: "Open Principal's Desk"),
  HelpItem('s-council', 'Setup', 'How do I run the Student Council elections?', [
    'IT / Principal: Student Council → Members & elections → New year (the posts are copied from last year).',
    'Elections → Start preparing → choose who can vote and when voting closes → Add candidate for each post (photo, class, one line).',
    'Open voting — students are told. Watch the totals; close voting; then Publish the new council. In a tie you choose the winner.',
    'The new council becomes the main tab; earlier councils stay as year tabs.',
  ], keywords: 'student council election vote candidates head boy head girl publish results', route: '/staff/council/manage', button: 'Open Student Council'),
  HelpItem('s-settings', 'Setup', 'How do I switch a feature off or change who sees a page?', [
    'IT: open School settings.',
    '“Who can use what” — tick the roles that see each page. “Features” — switch features on or off for families.',
  ], keywords: 'settings permission access role feature switch off hide page', route: '/staff/settings', button: 'Open School settings'),
  HelpItem('s-import', 'Setup', 'How do I import a list from Excel?', [
    'Open School setup → Import from Excel.',
    'Choose what you are importing and upload the file. Columns are matched for you.',
    'Check the list of problems (nothing is saved yet), then tap Import.',
  ], keywords: 'excel import upload sheet list bulk mcb', route: '/staff/setup', button: 'Open School setup'),
  HelpItem('s-classes', 'Setup', 'How do I change a class teacher or subject teacher?', [
    'Open School setup → Classes → tap the class.',
    'Choose the class teacher and the teacher for each subject, then Save.',
  ], keywords: 'class teacher subject teacher assign section', route: '/staff/setup', button: 'Open School setup'),
  // ---- Release F
  HelpItem('t-search', 'Getting started', 'How do I find a student quickly?', ['Click the search box at the top of any page, or press Ctrl + K (⌘ + K on a Mac).', 'Type 2–3 letters of the name, the admission number, a parent’s phone or a receipt number.', 'Use ↑ ↓ and Enter, or click the student. You only see students you are allowed to see.'], keywords: 'search find student phone receipt admission ctrl k'),
  HelpItem('t-attendance', 'Class', 'How do I take attendance?', ['Open Attendance. Everyone starts as present.', 'Tap the students who are absent (tap again for late), then Save.', 'Families of absent students are told at once. You can correct the last 7 days; older days go to the office.'], keywords: 'attendance absent present late register', route: '/staff/attendance', button: 'Open Attendance'),
  HelpItem('t-also-send', 'Class', 'Can I post the same homework to my other sections?', ['Yes. When you post in the diary, “Also send to” lists your other sections of the same grade for the same subject, already ticked.', 'Untick any you don’t want. Other grades are never offered.'], keywords: 'diary post other sections same homework', route: '/staff/diary', button: 'Open Diary'),
  HelpItem('t-undo', 'Getting started', 'I deleted something by mistake', ['Tap Undo on the bar at the bottom right away.', 'Later: IT or the Principal can bring it back from the Bin (in School setup) for 30 days.'], keywords: 'delete undo bin restore mistake'),
  HelpItem('t-msg-edit', 'Parents', 'Can I edit or delete a message I sent?', ['Press and hold your message (right-click on a laptop) → Edit or Delete for everyone.', 'Allowed for 2 days after sending.'], keywords: 'message delete edit wrong unsend chat'),
  HelpItem('t-notice-unsend', 'Notices', 'Can I take back a notice?', ['Tap ⋮ on the notice → Unsend, within 10 minutes. It disappears from every phone.', 'After that the office can delete it. You can always Edit it; families see “Updated”.'], keywords: 'notice unsend delete edit wrong'),
  HelpItem('s-houses', 'Setup', 'How do I add house points?', ['Open Honours → Houses. Tap the house, type the points and a short reason, then Add.', 'Coordinators, the office and the Principal can add points. IT / the Principal can let other teachers add them under House in-charges.', 'A wrong entry: tap the bin icon next to it (Undo is offered).'], keywords: 'house points athena ares artemis apollo pe add', route: '/staff/houses', button: 'Open Houses'),
  HelpItem('s-thanks', 'Class', 'Where are my Teachers’ Day thank-you notes?', ['During Teachers’ Day week a gold card on Today shows your notes. Tap it to open your wall.', 'The notes stay with you after the week.'], keywords: 'thank you notes teachers day wall', route: '/staff/thanks', button: 'Open my wall'),
  HelpItem('staff_approvals', 'Office', 'Where do I approve things?', ['Open Approvals in the menu. The number next to it shows how many are waiting.', 'The Principal decides three things there: receipt cancellations, TC requests and data corrections (name, date of birth, parents’ names).', 'The office and IT also see password help and certificates still to give.', 'Leave requests are not here — the class teacher approves them on the Leave requests page.'], keywords: 'approve approvals password leave receipt cancel certificate tc correction', route: '/staff/approvals', button: 'Open Approvals'),
  HelpItem('t-inactive', 'Setup', 'A teacher has left. What do I do?', ['School setup → Staff → open the teacher → switch off “Working here”.', 'Choose who takes each of their classes, then Make inactive. Everything they wrote stays.'], keywords: 'staff left inactive resign handover classes', needs: '/staff/users'),
  HelpItem('t-tour', 'Getting started', 'How do I see the app tour again?', ['Open Help at the bottom of the menu.', 'Tap “Take the tour again” at the top.'], keywords: 'tour guide intro walkthrough how to use new'),
  HelpItem('o-cert', 'Office', 'How do I print a TC, Study, Bonafide or No dues certificate?', ['Open Certificates → type the student’s name or admission number (past students are found too).', 'Tap the certificate. What the app knows is filled in; yellow boxes are for you to type in. Every box can be changed.', 'Tap Print / PDF. The certificate gets its own number (for example RCISKN/TC/2026-27/0001) and is kept, so it can be printed again exactly the same from “Issued recently”.', 'A No dues certificate can be printed only when no fees are due till today.'], keywords: 'tc transfer certificate study bonafide no dues certificate print issue reprint leaving', route: '/staff/certificates', button: 'Open Certificates'),
  HelpItem('s-idcards', 'Office', 'How do I print ID cards?', ['Open ID cards and pick a class, or All classes.', 'The "Not ready" list shows what is missing for each student (photo, blood group, parent phone, address, bus route).', 'Tap Print: the ready cards come on A4 at the real card size, fronts on one page and backs on the next. Print both sides, flip on long edge, actual size (100%).', 'For the card printer, tap Excel / photos pack.', 'When every student is ready, the page and the ID cards menu item glow gold.'], keywords: 'id card identity print vendor photo blood group', route: '/staff/id-cards', button: 'Open ID cards'),
  // ---- Release H
  HelpItem('o-correction', 'Office', 'How do I correct a student’s name or date of birth?', ['Open Students → the student → Edit details. Change what is needed and tap Save.', 'The name, date of birth, father’s name and mother’s name appear on certificates, so the Principal approves those first. Type why (for example “birth certificate seen”) and tap Send.', 'Everything else (address, phones, blood group…) is saved at once.', 'The student’s page shows “Waiting for the Principal” until it is decided. You get a notification either way.'], keywords: 'correct correction name spelling date of birth dob father mother change wrong', route: '/staff/students', button: 'Open Students'),
  HelpItem('p-decide', 'Office', 'How do I approve a data correction, TC or receipt cancellation?', ['Open Approvals. Each card shows what is asked, who asked and why.', 'Tap Approve or Decline. On Decline you can add a line for the office.', 'An approved correction is saved in the student’s record and written in the activity log. An approved TC gets its number and the office prints it from Certificates.'], keywords: 'principal approve decline correction tc receipt cancel', route: '/staff/approvals', button: 'Open Approvals', needs: '/staff/desk'),
  HelpItem('a-cancel', 'Office', 'I asked for a receipt to be cancelled. What happened?', ['Accounts: your Today page shows “Receipt cancellations you asked for” — waiting, cancelled or not approved, with the Principal’s note.', 'You also get a notification when it is decided.'], keywords: 'receipt cancel status accounts principal waiting', route: '/staff/fees', button: 'Open Fees & receipts'),
];

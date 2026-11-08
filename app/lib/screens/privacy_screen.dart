import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/config.dart';
import '../core/theme.dart';
import 'academics_screens.dart' show AppPage;

/// The privacy policy in plain English — from the sign-in page, Profile and Settings (no sign-in needed).
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const _parts = <(String, String)>[
    ('Whose information this is',
        'The information in Royale Connect belongs to Royale Concorde International School (“the school”). The school uses this app to run day-to-day school work with families. '
        'The app’s makers only look after it on the school’s behalf.'),
    ('What we keep',
        'The student’s name, admission number, date of birth, class, photo (only if you allow photos), parents’ names and phone numbers, address, '
        'fees and receipts, marks and report cards, attendance, the school bus stop, and messages between you and the school.'),
    ('Why we keep it',
        'To teach and look after your child, to keep you informed, to collect fees and give receipts, to run the school bus safely, and as the law requires (for example CBSE records).'),
    ('Who can see it',
        'Only school staff who need it for their work — for example, the class teacher sees their own class and the accounts office sees fees. '
        'Private messages between a parent and a teacher are seen only by the two of them. Aadhaar and other government ID numbers are never shown in the app.'),
    ('What we never do',
        'We never sell your information, never use it for advertising, and never share it with anyone outside the school except where the law requires.'),
    ('Bus location',
        'The bus driver’s phone shares the bus location only during a trip, so you can see where the bus is. Your own phone’s location is used only when you choose to (for example, to mark your pickup point) and is never tracked.'),
    ('How long we keep it',
        'Official school records — the student’s name, date of birth, admission number, parents’ names, phone numbers, classes, transfer certificate, marksheets and certificates — '
        'are kept permanently, as school records must be. Everything else — messages, photos, diary entries and notifications — is removed one year after the student leaves the school.'),
    ('Your choices',
        'You can ask the school office to show you your child’s information, to correct it, or to delete your Royale Connect account (Settings → Request account deletion). '
        'Official school records are kept even after the account is deleted, as the law requires.'),
    ('Keeping it safe',
        'Everything travels encrypted. Each family sees only their own children. Please do not share your password; you can change it any time in Settings.'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppPage(title: 'Privacy policy', body: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
      children: [
        Text('In short: your child’s information belongs to the school, is used only for school work, and is never sold.',
            style: TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w700, color: cs.onSurface)),
        const SizedBox(height: 18),
        for (final (h, b) in _parts) Padding(padding: const EdgeInsets.only(bottom: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(h, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: context.tone(Brand.crimsonDeep))),
          const SizedBox(height: 4),
          Text(b, style: TextStyle(height: 1.55, color: cs.onSurface)),
        ])),
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Brand.gold.withValues(alpha: .4))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Questions? Please contact the school office', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('${AppConfig.schoolName}\n6th B Main, HRBR Layout 2nd Block, Kalyan Nagar, Bengaluru 560043\n${AppConfig.officePhones}', style: TextStyle(height: 1.5, color: cs.onSurfaceVariant)),
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: () => launchUrl(Uri.parse('tel:${AppConfig.officePhone}')), icon: const Icon(Icons.call_rounded), label: const Text('Call the school office')),
          ])),
      ],
    ))));
  }
}

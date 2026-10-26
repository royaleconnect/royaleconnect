import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/config.dart';
import '../core/data.dart' show db;
import '../core/theme.dart';
import '../widgets/common.dart';

/// Public page opened by the QR code on a receipt or report card. No sign-in needed.
/// It shows only what is printed on the document itself, so anyone can confirm the paper is genuine.
class VerifyScreen extends StatefulWidget {
  final String kind, id; // kind: 'p' = fee receipt, 'c' = report card
  const VerifyScreen({super.key, required this.kind, required this.id});
  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  late final Future<Map<String, dynamic>> _check = _load();

  Future<Map<String, dynamic>> _load() async {
    if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(widget.id)) return {'ok': false};
    final r = await db.rpc('verify_document', params: {'kind': widget.kind, 'ref': widget.id});
    return Map<String, dynamic>.from(r as Map);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(body: Column(children: [
      const BrandHeader(padding: EdgeInsets.fromLTRB(20, 14, 20, 16), child: Text('Document check', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800))),
      Expanded(child: FutureBuilder<Map<String, dynamic>>(future: _check, builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        final m = snap.data ?? const {'ok': false};
        final ok = snap.hasError ? null : m['ok'] == true;
        Widget line(String k, String? v) => v == null || v.isEmpty ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(k, style: TextStyle(color: cs.onSurfaceVariant))),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w700))),
        ]));
        final date = m['date'] == null ? null : DateFormat('d MMMM yyyy').format(DateTime.parse(m['date']).toLocal());
        return ListView(padding: const EdgeInsets.all(20), children: [
          Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(22)), child: Column(children: [
            Container(width: 68, height: 68, alignment: Alignment.center,
                decoration: BoxDecoration(color: ok == true ? Brand.greenTint : ok == false ? Brand.crimsonTint : Brand.amberTint, shape: BoxShape.circle),
                child: Icon(ok == true ? Icons.verified_rounded : ok == false ? Icons.gpp_bad_rounded : Icons.wifi_off_rounded,
                    color: ok == true ? Brand.green : ok == false ? Brand.crimson : Brand.amber, size: 38)),
            const SizedBox(height: 14),
            Text(ok == true ? 'Genuine ${'${m['type']}'.toLowerCase()}' : ok == false ? 'Not found in the school’s records' : 'Could not check right now',
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(ok == true ? 'Issued by ${AppConfig.schoolName}. Check that the details below match the paper.'
                : ok == false ? 'This document was not issued through Royale Connect, or it has been changed. Please contact the school office.'
                : 'Please check the internet connection and open the link again.',
                textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
            if (ok == true) ...[
              const Divider(height: 32),
              line(m['type'] == 'Fee receipt' ? 'Receipt No.' : 'Report', m['number']?.toString()),
              line('Student', m['student']?.toString()),
              line('Admission No.', m['admission_no']?.toString()),
              line('Class', m['class']?.toString()),
              if (m['amount'] != null) line('Amount paid', inr(m['amount'] as num)),
              line(m['type'] == 'Fee receipt' ? 'Paid on' : 'Issued on', date),
            ],
          ])),
        ]);
      })),
    ]));
  }
}

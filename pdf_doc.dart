import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'api.dart';
import 'util.dart';

String _m(dynamic v) => inr(v).replaceFirst('₹', '');
String _g(dynamic v) {
  final n = numOf(v);
  return n == n.roundToDouble() ? n.toInt().toString() : n.toString();
}

/// Builds an A4 invoice / quotation / delivery-note PDF on the phone.
Future<Uint8List> buildPdf(Map d, Map biz, {bool deliveryNote = false}) async {
  final reg = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
  final doc = pw.Document(theme: pw.ThemeData.withFont(base: reg, bold: bold));
  final cust = (d['customer'] ?? {}) as Map;
  final cur = '${biz['currency'] ?? '₹'}';
  final nav = PdfColor.fromInt(0xFF0B1F44);
  final goldc = PdfColor.fromInt(0xFFC9A227);
  final type = '${d['type']}';
  final title = deliveryNote ? 'DELIVERY NOTE' : (type == 'invoice' ? 'INVOICE' : type == 'quotation' ? 'QUOTATION' : 'PRO FORMA INVOICE');

  pw.MemoryImage? logo;
  final lf = '${biz['logo'] ?? ''}';
  if (lf.isNotEmpty && biz['show_logo'] == '1' && !lf.toLowerCase().endsWith('.webp') && !lf.toLowerCase().endsWith('.pdf')) {
    final b = await Api.bytes('/uploads/$lf');
    if (b != null) {
      try {
        logo = pw.MemoryImage(b);
      } catch (_) {}
    }
  }

  pw.Widget cell(String t, {bool right = false, bool head = false, bool strong = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        child: pw.Text(t,
            textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(fontSize: 9.5, color: head ? PdfColors.white : PdfColors.black, fontWeight: (head || strong) ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );

  final logoImg = logo;
  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: pw.BoxDecoration(color: nav),
      children: [
        cell('#', head: true),
        cell('Description', head: true),
        cell('Qty', head: true, right: true),
        if (!deliveryNote) ...[cell('Rate', head: true, right: true), cell('Disc%', head: true, right: true), cell('Tax%', head: true, right: true), cell('Amount', head: true, right: true)],
      ],
    ),
  ];
  var n = 0;
  for (final l in (d['items'] as List)) {
    n++;
    final desc = '${l['desc'] ?? ''}'.trim();
    rows.add(pw.TableRow(
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300))),
      children: [
        cell('$n'),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('${l['name']}', style: const pw.TextStyle(fontSize: 9.5)),
            if (desc.isNotEmpty) pw.Text(desc, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          ]),
        ),
        cell(_g(l['qty']), right: true),
        if (!deliveryNote) ...[cell(_m(l['rate']), right: true), cell(_g(l['disc']), right: true), cell(_g(l['tax_rate']), right: true), cell(_m(l['gross']), right: true)],
      ],
    ));
  }
  if (!deliveryNote) {
    for (final x in (d['charges'] as List)) {
      rows.add(pw.TableRow(children: [cell(''), cell('${x['name']}'), cell(''), cell(''), cell(''), cell(_g(x['tax_rate']), right: true), cell(_m(x['amount']), right: true)]));
    }
  }

  pw.Widget tot(String a, String b, {bool big = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(a, style: pw.TextStyle(fontSize: big ? 12 : 9.5, fontWeight: big ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(b, style: pw.TextStyle(fontSize: big ? 12 : 9.5, fontWeight: big ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ]),
      );

  final tax = numOf(d['tax']);
  final isInv = type == 'invoice' && d['status'] == 'issued';
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(30),
    build: (_) => [
      pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 10),
        decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: goldc, width: 3))),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              if (logoImg != null) pw.SizedBox(height: 46, child: pw.Image(logoImg)),
              pw.Text('${biz['biz_name'] ?? ''}', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: nav)),
              pw.Text(
                  [biz['address'], if ('${biz['phone'] ?? ''}'.isNotEmpty) 'Phone: ${biz['phone']}', biz['email'], biz['website'], if ('${biz['gstin'] ?? ''}'.isNotEmpty) 'GSTIN: ${biz['gstin']}', if ('${biz['pan'] ?? ''}'.isNotEmpty) 'PAN: ${biz['pan']}']
                      .where((e) => e != null && '$e'.isNotEmpty)
                      .join('\n'),
                  style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
            ]),
          ),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text(title, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: nav)),
            pw.Text('${d['number'] ?? 'DRAFT'}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.Text('Date: ${d['issue_date']}', style: const pw.TextStyle(fontSize: 9)),
            if ('${d['due_date'] ?? ''}'.isNotEmpty && '${d['due_date']}' != 'null') pw.Text('Due: ${d['due_date']}', style: const pw.TextStyle(fontSize: 9)),
          ]),
        ]),
      ),
      pw.SizedBox(height: 12),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('Bill to', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey600)),
          pw.Text('${cust['name'] ?? ''}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.Text(
              [cust['org'], cust['address'], [cust['city'], cust['pin']].where((e) => e != null && '$e'.isNotEmpty).join(' '), cust['state'], if ('${cust['gstin'] ?? ''}'.isNotEmpty) 'GSTIN: ${cust['gstin']}', cust['phone']]
                  .where((e) => e != null && '$e'.isNotEmpty)
                  .join('\n'),
              style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
        ]),
        if ('${d['project'] ?? ''}'.isNotEmpty && '${d['project']}' != 'null')
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('Project', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey600)),
            pw.Text('${d['project']}', style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
          ]),
      ]),
      pw.SizedBox(height: 10),
      pw.Table(
        columnWidths: deliveryNote
            ? {0: const pw.FixedColumnWidth(24), 1: const pw.FlexColumnWidth(5), 2: const pw.FixedColumnWidth(40)}
            : {0: const pw.FixedColumnWidth(22), 1: const pw.FlexColumnWidth(4), 2: const pw.FixedColumnWidth(30), 3: const pw.FixedColumnWidth(60), 4: const pw.FixedColumnWidth(36), 5: const pw.FixedColumnWidth(34), 6: const pw.FixedColumnWidth(66)},
        children: rows,
      ),
      if (!deliveryNote) ...[
        pw.SizedBox(height: 8),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.SizedBox(
            width: 210,
            child: pw.Column(children: [
              tot('Subtotal', _m(d['subtotal'])),
              if (numOf(d['disc_total']) > 0) tot('Discount', '- ${_m(d['disc_total'])}'),
              if (numOf(d['coupon_disc']) > 0) tot('Coupon ${d['coupon'] ?? ''}', '- ${_m(d['coupon_disc'])}'),
              if (numOf(d['charges_total']) > 0) tot('Additional charges', _m(d['charges_total'])),
              if (tax > 0 && d['tax_mode'] == 'intra') ...[tot('CGST', _m(tax / 2)), tot('SGST', _m(tax / 2))] else if (tax > 0) tot('IGST', _m(tax)),
              if (numOf(d['round_amt']) != 0) tot('Round off', _m(d['round_amt'])),
              pw.Divider(color: nav, thickness: 1.5),
              tot('Total ($cur)', _m(d['total']), big: true),
              if (isInv) ...[tot('Paid', _m(d['net_paid'])), tot('Balance due', _m(d['balance']), big: true)],
            ]),
          ),
        ),
      ],
      if ('${d['delivery'] ?? ''}'.isNotEmpty && '${d['delivery']}' != 'null') pw.Padding(padding: const pw.EdgeInsets.only(top: 8), child: pw.Text('Delivery: ${d['delivery']}', style: const pw.TextStyle(fontSize: 9))),
      if (!deliveryNote && '${biz['pay_instr'] ?? ''}'.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 8), child: pw.Text('Payment instructions\n${biz['pay_instr']}', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700))),
      if ('${d['notes'] ?? ''}'.isNotEmpty && '${d['notes']}' != 'null') pw.Padding(padding: const pw.EdgeInsets.only(top: 6), child: pw.Text('Notes\n${d['notes']}', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700))),
      if ('${d['terms'] ?? ''}'.isNotEmpty && '${d['terms']}' != 'null') pw.Padding(padding: const pw.EdgeInsets.only(top: 6), child: pw.Text('Terms & conditions\n${d['terms']}', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700))),
      pw.SizedBox(height: 24),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('${biz['footer'] ?? ''}', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
        pw.Text('Authorised signatory${'${biz['owner'] ?? ''}'.isNotEmpty ? ' - ${biz['owner']}' : ''}', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
      ]),
    ],
  ));
  return doc.save();
}

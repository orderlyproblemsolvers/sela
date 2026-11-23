import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'note.dart';

class NoteIO {
  /// Converts a Note's Quill Delta to clean Markdown.
  static String toMarkdown(Note note) {
    final buf = StringBuffer();
    if (note.title.trim().isNotEmpty) {
      buf.writeln('# ${note.title.trim()}\n');
    }

    final ops = note.delta;
    var lineBuf = StringBuffer();

    void flushLine(Map<String, dynamic>? lineAttrs) {
      final text = lineBuf.toString();
      lineBuf = StringBuffer();
      if (lineAttrs != null) {
        final header = lineAttrs['header'];
        final list = lineAttrs['list'];
        final blockquote = lineAttrs['blockquote'];
        if (header == 1) {
          buf.writeln('# $text');
          return;
        } else if (header == 2) {
          buf.writeln('## $text');
          return;
        } else if (header == 3) {
          buf.writeln('### $text');
          return;
        } else if (list == 'bullet') {
          buf.writeln('- $text');
          return;
        } else if (list == 'ordered') {
          buf.writeln('1. $text');
          return;
        } else if (list == 'checked') {
          buf.writeln('- [x] $text');
          return;
        } else if (list == 'unchecked') {
          buf.writeln('- [ ] $text');
          return;
        } else if (blockquote == true) {
          buf.writeln('> $text');
          return;
        }
      }
      buf.writeln(text);
    }

    for (final raw in ops) {
      if (raw is! Map) continue;
      final data = raw['insert'];
      if (data is! String) continue;
      final attrs = (raw['attributes'] as Map?)?.cast<String, dynamic>();

      if (data.contains('\n')) {
        final parts = data.split('\n');
        for (var i = 0; i < parts.length; i++) {
          final seg = parts[i];
          if (seg.isNotEmpty) {
            lineBuf.write(_formatInline(seg, attrs));
          }
          if (i < parts.length - 1) {
            // In Quill Delta, attributes on a '\n' apply to the line
            flushLine(data == '\n' ? attrs : null);
          }
        }
      } else {
        lineBuf.write(_formatInline(data, attrs));
      }
    }

    if (lineBuf.isNotEmpty) {
      buf.writeln(lineBuf.toString());
    }
    return buf.toString().trimRight();
  }

  static String _formatInline(String text, Map<String, dynamic>? attrs) {
    if (attrs == null || text.isEmpty) return text;
    var out = text;
    if (attrs['bold'] == true) out = '**$out**';
    if (attrs['italic'] == true) out = '*$out*';
    if (attrs['strike'] == true) out = '~~$out~~';
    return out;
  }

  /// Parses a Markdown file into a Note with Quill Delta formatting.
  static Note fromMarkdown(String markdown, {String? fallbackTitle}) {
    final lines = markdown.replaceAll('\r\n', '\n').split('\n');
    String title = fallbackTitle ?? '';
    var startIdx = 0;

    if (lines.isNotEmpty && lines.first.startsWith('# ')) {
      title = lines.first.substring(2).trim();
      startIdx = 1;
      if (startIdx < lines.length && lines[startIdx].trim().isEmpty) {
        startIdx++;
      }
    }

    final delta = Delta();
    final plainBuf = StringBuffer();

    for (var i = startIdx; i < lines.length; i++) {
      var line = lines[i];
      Map<String, dynamic>? lineAttr;

      if (line.startsWith('### ')) {
        line = line.substring(4);
        lineAttr = {'header': 3};
      } else if (line.startsWith('## ')) {
        line = line.substring(3);
        lineAttr = {'header': 2};
      } else if (line.startsWith('# ')) {
        line = line.substring(2);
        lineAttr = {'header': 1};
      } else if (line.startsWith('- [x] ') || line.startsWith('- [X] ')) {
        line = line.substring(6);
        lineAttr = {'list': 'checked'};
      } else if (line.startsWith('- [ ] ')) {
        line = line.substring(6);
        lineAttr = {'list': 'unchecked'};
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        line = line.substring(2);
        lineAttr = {'list': 'bullet'};
      } else if (RegExp(r'^\d+\.\s+').hasMatch(line)) {
        line = line.replaceFirst(RegExp(r'^\d+\.\s+'), '');
        lineAttr = {'list': 'ordered'};
      } else if (line.startsWith('> ')) {
        line = line.substring(2);
        lineAttr = {'blockquote': true};
      }

      _insertInlineMarkdown(delta, plainBuf, line);
      delta.insert('\n', lineAttr);
      plainBuf.writeln();
    }

    if (delta.isEmpty) delta.insert('\n');
    final plain = plainBuf.toString().trim();
    final preview = plain.length <= 280 ? plain : '${plain.substring(0, 280)}…';

    return Note(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      plain: plain,
      preview: preview,
      delta: delta.toJson(),
    );
  }

  static void _insertInlineMarkdown(
      Delta delta, StringBuffer plainBuf, String text) {
    final pattern = RegExp(r'(\*\*(.+?)\*\*|\*(.+?)\*|~~(.+?)~~)');
    var last = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > last) {
        final seg = text.substring(last, m.start);
        delta.insert(seg);
        plainBuf.write(seg);
      }
      if (m.group(2) != null) {
        delta.insert(m.group(2)!, {'bold': true});
        plainBuf.write(m.group(2)!);
      } else if (m.group(3) != null) {
        delta.insert(m.group(3)!, {'italic': true});
        plainBuf.write(m.group(3)!);
      } else if (m.group(4) != null) {
        delta.insert(m.group(4)!, {'strike': true});
        plainBuf.write(m.group(4)!);
      }
      last = m.end;
    }
    if (last < text.length) {
      final tail = text.substring(last);
      delta.insert(tail);
      plainBuf.write(tail);
    }
  }

  /// Generates a clean PDF document for a single Note.
  static Future<Uint8List> toPdfBytes(Note note) async {
    final pdf = pw.Document();
    final lines = note.plain.split('\n');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(42),
        build: (context) => [
          pw.Text(
            note.displayTitle,
            style: pw.TextStyle(
              fontSize: 24,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (note.tags.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              note.tags.map((t) => '#$t').join('  '),
              style: const pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey700,
              ),
            ),
          ],
          pw.SizedBox(height: 14),
          pw.Divider(color: PdfColors.grey300),
          pw.SizedBox(height: 14),
          for (final line in lines)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Text(
                line,
                style: const pw.TextStyle(fontSize: 12, lineSpacing: 4),
              ),
            ),
        ],
      ),
    );
    return pdf.save();
  }

  /// Saves or shares a file across Web, Desktop (Windows/macOS/Linux), and Mobile.
  static Future<void> saveOrShareFile({
    required BuildContext context,
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (kIsWeb) {
        // On Web, XFile.fromData triggers a browser download or Web Share sheet
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile.fromData(bytes, name: fileName, mimeType: mimeType)],
            subject: fileName,
          ),
        );
        return;
      }

      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final uri = await FilePicker.saveFile(
          dialogTitle: 'Export $fileName',
          fileName: fileName,
          bytes: bytes,
          mimeType: mimeType,
        );
        if (uri == null) return;
        if (uri.scheme == 'file') {
          await File(uri.toFilePath()).writeAsBytes(bytes);
        }
        messenger
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text('Saved $fileName')));
      } else {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(bytes);
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: mimeType)],
            subject: fileName,
          ),
        );
      }
    } catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }
}
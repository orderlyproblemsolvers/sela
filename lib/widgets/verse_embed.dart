import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../bible/verse_ref.dart';

const String kVerseEmbedType = 'verse';

/// Legacy: shows old embedded verse cards as a simple underlined label.
class VerseEmbedBuilder extends EmbedBuilder {
  @override
  String get key => kVerseEmbedType;

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    var label = 'verse';
    try {
      label = VerseRef.fromJson(
        jsonDecode(embedContext.node.value.data as String)
            as Map<String, dynamic>,
      ).label;
    } catch (_) {}
    return Text(
      label,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.dotted,
        decorationColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

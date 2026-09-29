import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

enum LogKind {
  /// Octets reçus de la carte.
  rx,

  /// Octets envoyés par l'utilisateur.
  tx,

  /// Message de l'application (connexion, hotplug…).
  system,

  error,
}

/// Une ligne du moniteur. On conserve les octets bruts pour pouvoir basculer
/// entre les vues texte et hexadécimale sans perte.
@immutable
class LogEntry {
  LogEntry({required this.kind, required this.bytes, DateTime? time}) : time = time ?? DateTime.now();

  factory LogEntry.system(String message) => LogEntry(kind: LogKind.system, bytes: utf8.encode(message));

  factory LogEntry.error(String message) => LogEntry(kind: LogKind.error, bytes: utf8.encode(message));

  final LogKind kind;
  final Uint8List bytes;
  final DateTime time;

  /// Texte affichable, calculé à la demande (une seule fois).
  late final String text = terminalText(bytes);

  late final String hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join(' ');
}

final _ansiEscape = RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]');
final _controlChars = RegExp(r'[\x00-\x08\x0B-\x1F\x7F]');

/// Décode l'UTF-8 (sans jamais échouer), puis retire les séquences ANSI
/// (couleurs des logs ESP-IDF) et les caractères de contrôle, dont `\r`.
String terminalText(Uint8List bytes) => utf8
    .decode(bytes, allowMalformed: true)
    .replaceAll(_ansiEscape, '')
    .replaceAll(_controlChars, '');

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Ouvre une adresse dans le navigateur ; faux si c'est impossible. Dans les tests : un faux.
final linkOpenerProvider = Provider<Future<bool> Function(Uri url)>(
  (ref) => (url) async {
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  },
);

/// Ouvre [url] ; si aucun navigateur ne répond, copie l'adresse et renvoie faux.
Future<bool> openOrCopy(WidgetRef ref, Uri url) async {
  if (await ref.read(linkOpenerProvider)(url)) return true;
  await Clipboard.setData(ClipboardData(text: url.toString()));
  return false;
}

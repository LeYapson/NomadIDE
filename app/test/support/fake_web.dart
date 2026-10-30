import 'dart:convert';
import 'dart:typed_data';

import 'package:nomad_mcu/features/flash/data/firmware_catalog.dart';

/// Faux réseau : des réponses par adresse ; une adresse inconnue répond 404.
class FakeWeb implements FirmwareSource {
  final Map<String, Uint8List> pages = {};
  final List<Uri> requested = [];
  bool offline = false;

  void text(String url, String body) => pages[url] = Uint8List.fromList(utf8.encode(body));

  @override
  Future<String> fetchText(Uri url) async => utf8.decode(await fetchBytes(url));

  @override
  Future<Uint8List> fetchBytes(Uri url, {void Function(int done, int? total)? onProgress}) async {
    requested.add(url);
    if (offline) throw FirmwareException(FirmwareError.network, host: url.host);
    final page = pages[url.toString()];
    if (page == null) throw FirmwareException(FirmwareError.badStatus, host: url.host, status: 404);
    return page;
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_mcu/features/flash/application/firmware_controller.dart';
import 'package:nomad_mcu/features/flash/data/firmware_catalog.dart';

import 'support/locale.dart';

/// Page de téléchargement de micropython.org, avec versions stables, préversions et variantes.
const _espPage = '''
<a href="/resources/firmware/ESP32_GENERIC-20261028-v1.30.0-preview.188.g29d45e488c.bin">preview</a>
<a href="/resources/firmware/ESP32_GENERIC-20260406-v1.28.0.bin">v1.28.0</a>
<a href="/resources/firmware/ESP32_GENERIC-20260824-v1.29.0.bin">v1.29.0</a>
<a href="/resources/firmware/ESP32_GENERIC-UNICORE-20261201-v1.31.0.bin">autre variante</a>
<a href="/resources/firmware/ESP32_GENERIC-OTA-20261101-v1.30.0.bin">autre variante</a>
<a href="/resources/firmware/ESP32_GENERIC-20260824-v1.29.0.app-bin">app</a>
''';

const _picoPage = '''
<a href="/resources/firmware/RPI_PICO-20260824-v1.29.0.uf2">v1.29.0</a>
<a href="/resources/firmware/RPI_PICO-20260406-v1.28.0.uf2">v1.28.0</a>
<a href="/resources/firmware/RPI_PICO-20261001-v1.30.0-preview.1.gabc.uf2">preview</a>
''';

String _badgerJson() => jsonEncode({
      'tag_name': 'v0.0.5',
      'assets': [
        {
          'name': 'pimoroni-badger2040-v0.0.5-micropython-with-badger-os.uf2',
          'browser_download_url': 'https://github.com/pimoroni/badger2040/releases/download/v0.0.5/pimoroni-badger2040-v0.0.5-micropython-with-badger-os.uf2',
        },
        {
          'name': 'pimoroni-badger2040-v0.0.5-micropython.uf2',
          'browser_download_url': 'https://github.com/pimoroni/badger2040/releases/download/v0.0.5/pimoroni-badger2040-v0.0.5-micropython.uf2',
        },
        {
          'name': 'pimoroni-badger2040w-v0.0.5-micropython.uf2',
          'browser_download_url': 'https://github.com/pimoroni/badger2040/releases/download/v0.0.5/pimoroni-badger2040w-v0.0.5-micropython.uf2',
        },
      ],
    });

class FakeFirmwareSource implements FirmwareSource {
  FakeFirmwareSource({this.pages = const {}, this.files = const {}});

  final Map<String, String> pages;
  final Map<String, Uint8List> files;
  final List<Uri> requested = [];
  Object? failWith;

  @override
  Future<String> fetchText(Uri url) async {
    requested.add(url);
    final error = failWith;
    if (error != null) throw error;
    return pages[url.toString()] ?? (throw FirmwareException(FirmwareError.badStatus, host: url.host, status: 404));
  }

  @override
  Future<Uint8List> fetchBytes(Uri url, {void Function(int done, int? total)? onProgress}) async {
    requested.add(url);
    final error = failWith;
    if (error != null) throw error;
    final bytes = files[url.toString()] ?? (throw FirmwareException(FirmwareError.badStatus, host: url.host, status: 404));
    onProgress?.call(bytes.length ~/ 2, bytes.length);
    onProgress?.call(bytes.length, bytes.length);
    return bytes;
  }
}

void main() {
  final source = FakeFirmwareSource(
    pages: {
      'https://micropython.org/download/ESP32_GENERIC/': _espPage,
      'https://micropython.org/download/RPI_PICO/': _picoPage,
      'https://api.github.com/repos/pimoroni/badger2040/releases/latest': _badgerJson(),
    },
    files: {
      'https://micropython.org/resources/firmware/ESP32_GENERIC-20260824-v1.29.0.bin': Uint8List.fromList(List.filled(3000, 7)),
      'https://github.com/pimoroni/badger2040/releases/download/v0.0.5/pimoroni-badger2040-v0.0.5-micropython.uf2':
          Uint8List.fromList(List.filled(1024, 9)),
    },
  );
  late FirmwareCatalog catalog;

  setUp(() {
    source.requested.clear();
    source.failWith = null;
    catalog = FirmwareCatalog(source);
  });

  group('FirmwareCatalog', () {
    test('ESP32 : la dernière version stable, sans préversion ni variante', () async {
      final r = await catalog.latest(FirmwareBoard.esp32);
      expect(r.version, 'v1.29.0');
      expect(r.date, '20260824');
      expect(r.fileName, 'ESP32_GENERIC-20260824-v1.29.0.bin');
      expect(r.url.toString(), 'https://micropython.org/resources/firmware/ESP32_GENERIC-20260824-v1.29.0.bin');
    });

    test('Pico : fichier .uf2, préversion ignorée', () async {
      final r = await catalog.latest(FirmwareBoard.pico);
      expect(r.version, 'v1.29.0');
      expect(r.fileName, 'RPI_PICO-20260824-v1.29.0.uf2');
    });

    test('Badger 2040 : le firmware Pimoroni seul, pas la version avec Badger OS ni la version W', () async {
      final r = await catalog.latest(FirmwareBoard.badger2040);
      expect(r.version, 'v0.0.5');
      expect(r.fileName, 'pimoroni-badger2040-v0.0.5-micropython.uf2');
      expect(r.url.host, 'github.com');
    });

    test('Badger 2040 W : la version W', () async {
      final r = await catalog.latest(FirmwareBoard.badger2040w);
      expect(r.fileName, 'pimoroni-badger2040w-v0.0.5-micropython.uf2');
    });

    test('carte dont la page n\'existe pas : erreur claire', () async {
      await expectLater(
        catalog.latest(FirmwareBoard.esp32s3),
        throwsA(isA<FirmwareException>().having((e) => e.error, 'error', FirmwareError.badStatus)),
      );
    });

    test('page sans aucune version stable : notFound', () async {
      final empty = FirmwareCatalog(FakeFirmwareSource(pages: {'https://micropython.org/download/ESP32_GENERIC/': '<html></html>'}));
      await expectLater(
        empty.latest(FirmwareBoard.esp32),
        throwsA(isA<FirmwareException>().having((e) => e.error, 'error', FirmwareError.notFound)),
      );
    });

    test('télécharge le fichier de la version trouvée', () async {
      final release = await catalog.latest(FirmwareBoard.esp32);
      final file = await catalog.download(release);
      expect(file.name, 'ESP32_GENERIC-20260824-v1.29.0.bin');
      expect(file.bytes, hasLength(3000));
    });

    test('refuse une adresse hors des sites officiels ou sans HTTPS', () async {
      for (final url in ['https://evil.example/fw.bin', 'http://micropython.org/fw.bin', 'https://micropython.org.evil.example/fw.bin']) {
        final release = FirmwareRelease(board: FirmwareBoard.esp32, version: 'v1', url: Uri.parse(url), fileName: 'fw.bin');
        await expectLater(
          catalog.download(release),
          throwsA(isA<FirmwareException>().having((e) => e.error, 'error', FirmwareError.untrustedSource)),
          reason: url,
        );
      }
      expect(source.requested, isEmpty);
    });

    test('une release GitHub dont le lien pointe ailleurs est refusée', () async {
      final hostile = FakeFirmwareSource(pages: {
        'https://api.github.com/repos/pimoroni/badger2040/releases/latest': jsonEncode({
          'tag_name': 'v9',
          'assets': [
            {'name': 'pimoroni-badger2040-v9-micropython.uf2', 'browser_download_url': 'https://evil.example/x.uf2'},
          ],
        }),
      });
      await expectLater(
        FirmwareCatalog(hostile).latest(FirmwareBoard.badger2040),
        throwsA(isA<FirmwareException>().having((e) => e.error, 'error', FirmwareError.untrustedSource)),
      );
    });
  });

  group('FirmwareController', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(overrides: [frenchLocale, firmwareSourceProvider.overrideWithValue(source)]);
      container.listen(firmwareProvider, (_, __) {});
    });

    tearDown(() => container.dispose());

    FirmwareController controller() => container.read(firmwareProvider.notifier);
    FirmwareState state() => container.read(firmwareProvider);

    test('chercher puis télécharger : le fichier est remis, avec un message de succès', () async {
      await controller().find(FirmwareBoard.esp32);
      expect(state().phase, FirmwarePhase.found);
      expect(state().release?.version, 'v1.29.0');
      // Rien n'est téléchargé avant le clic.
      expect(source.requested.where((u) => u.path.endsWith('.bin')), isEmpty);

      final file = await controller().download();
      expect(file?.name, 'ESP32_GENERIC-20260824-v1.29.0.bin');
      expect(file?.bytes, hasLength(3000));
      expect(state().phase, FirmwarePhase.downloaded);
      expect(state().message, contains('téléchargé'));
    });

    test('pas de réseau : message avec le site et la cause', () async {
      source.failWith = const FirmwareException(FirmwareError.network, host: 'micropython.org', cause: 'SocketException');
      await controller().find(FirmwareBoard.esp32);
      expect(state().phase, FirmwarePhase.failed);
      expect(state().message, contains('micropython.org'));
      expect(state().message, contains('connexion Internet'));
    });

    test('download sans recherche préalable ne fait rien', () async {
      expect(await controller().download(), isNull);
      expect(source.requested, isEmpty);
    });

    test('changer de carte efface la version trouvée', () async {
      await controller().find(FirmwareBoard.esp32);
      controller().selectBoard(FirmwareBoard.esp32s3);
      expect(state().release, isNull);
      expect(state().phase, FirmwarePhase.idle);
    });
  });
}

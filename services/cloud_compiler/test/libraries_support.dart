import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:nomad_cloud_compiler/nomad_cloud_compiler.dart';

const String fakeHash = 'a1b2c3d4e5f6a7b8a1b2c3d4e5f6a7b8a1b2c3d4e5f6a7b8a1b2c3d4e5f6a7b8';

/// Une entrée de `library_index.json`.
Map<String, Object?> releaseJson(
  String name,
  String version, {
  String author = 'Someone',
  String sentence = '',
  String paragraph = '',
  String category = 'Sensors',
  List<String> architectures = const ['*'],
  List<String> includes = const [],
  List<Map<String, String>> dependencies = const [],
  String? license = 'MIT',
  String? url,
  int size = 100,
  String? checksum,
}) =>
    {
      'name': name,
      'version': version,
      'author': author,
      'sentence': sentence,
      'paragraph': paragraph,
      'category': category,
      'architectures': architectures,
      'providesIncludes': includes,
      if (dependencies.isNotEmpty) 'dependencies': dependencies,
      if (license != null) 'license': license,
      'website': 'https://example.com/$name',
      'url': url ?? 'https://downloads.arduino.cc/libraries/github.com/${name.replaceAll(' ', '_')}-$version.zip',
      'size': size,
      'checksum': checksum ?? 'SHA-256:$fakeHash',
    };

String indexJson(List<Map<String, Object?>> releases) => jsonEncode({'libraries': releases});

/// Un petit catalogue qui sert à tous les tests.
List<Map<String, Object?>> sampleReleases() => [
      releaseJson('DHT sensor library', '1.3.10', author: 'Adafruit', sentence: 'Arduino library for DHT11, DHT22 sensors',
          includes: ['DHT.h', 'DHT_U.h'], dependencies: [
            {'name': 'Adafruit Unified Sensor'}
          ]),
      releaseJson('DHT sensor library', '1.4.4', author: 'Adafruit', sentence: 'Arduino library for DHT11, DHT22 sensors',
          paragraph: 'Temperature and humidity.', includes: ['DHT.h', 'DHT_U.h'], dependencies: [
            {'name': 'Adafruit Unified Sensor'}
          ]),
      releaseJson('DHT sensor library', '1.4.6', author: 'Adafruit', sentence: 'Arduino library for DHT11, DHT22 sensors',
          paragraph: 'Temperature and humidity.', includes: ['DHT.h', 'DHT_U.h'], dependencies: [
            {'name': 'Adafruit Unified Sensor', 'version': '>=1.1.0'}
          ]),
      releaseJson('Adafruit Unified Sensor', '1.1.4', author: 'Adafruit', sentence: 'Required for all Adafruit sensor libraries',
          includes: ['Adafruit_Sensor.h']),
      releaseJson('Adafruit Unified Sensor', '1.1.9', author: 'Adafruit', sentence: 'Required for all Adafruit sensor libraries',
          includes: ['Adafruit_Sensor.h']),
      releaseJson('DHT', '0.1.0', author: 'Other', sentence: 'Tiny DHT driver', includes: ['DHT.h']),
      releaseJson('Servo', '1.2.1', author: 'Arduino', sentence: 'Control servo motors', architectures: ['avr', 'esp32'], includes: ['Servo.h']),
      releaseJson('AvrOnly', '1.0.0', architectures: ['avr'], includes: ['AvrOnly.h']),
      releaseJson('Adafruit BusIO', '1.14.5', author: 'Adafruit', sentence: 'I2C and SPI helpers', includes: ['Adafruit_BusIO_Register.h'], dependencies: [
        {'name': 'Wire'},
        {'name': 'SPI'}
      ]),
      releaseJson('Beta lib', '1.0.0'),
      releaseJson('Beta lib', '2.0.0-beta.1'),
      releaseJson('Pre only', '0.9.0-rc1'),
    ];

LibraryIndex sampleIndex() => LibraryIndex.parse(indexJson(sampleReleases()));

/// Archive d'une bibliothèque : `<top>/library.properties` et un source, avec un dossier englobant comme dans l'index.
Uint8List libraryZip({String top = 'DHT-sensor-library-1.4.6', Map<String, String>? files}) {
  final archive = Archive();
  final content = files ?? {'library.properties': 'name=DHT sensor library\nversion=1.4.6\n', 'src/DHT.h': '#pragma once\n', 'src/DHT.cpp': '// dht\n'};
  content.forEach((name, text) {
    archive.add(ArchiveFile.bytes(top.isEmpty ? name : '$top/$name', utf8.encode(text)));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String sha256Of(List<int> bytes) => sha256.convert(bytes).toString();

/// Entrée d'index pour une archive réelle (adresse, taille et empreinte cohérentes).
LibraryRelease releaseFor(Uint8List zip, {String name = 'DHT sensor library', String version = '1.4.6', String? url}) {
  final index = LibraryIndex.parse(indexJson([
    releaseJson(name, version, url: url, size: zip.length, checksum: 'SHA-256:${sha256Of(zip)}'),
  ]));
  return index.release(name, version)!;
}

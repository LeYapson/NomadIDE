import 'package:nomad_compile_api/nomad_compile_api.dart';
import 'package:test/test.dart';

void main() {
  group('parseCompilerOutput', () {
    test('extrait erreur, colonne, chemin relatif et note', () {
      const out = '''
/work/sketch/blink.ino: In function 'void loop()':
/work/sketch/blink.ino:12:5: error: 'digitalWritee' was not declared in this scope
   digitalWritee(LED, HIGH);
/work/sketch/blink.ino:12:5: note: suggested alternative: 'digitalWrite'
/work/sketch/util.h:3:1: warning: unused variable 'x' [-Wunused-variable]
collect2: error: ld returned 1 exit status
''';
      final d = parseCompilerOutput(out, sourceRoots: ['/work/sketch']);
      expect(d, hasLength(2));
      expect(d[0].file, 'blink.ino');
      expect(d[0].line, 12);
      expect(d[0].column, 5);
      expect(d[0].severity, DiagnosticSeverity.error);
      expect(d[0].notes, ["blink.ino:12: suggested alternative: 'digitalWrite'"]);
      expect(d[1].file, 'util.h');
      expect(d[1].severity, DiagnosticSeverity.warning);
    });

    test('ligne sans colonne et chemin Windows', () {
      final d = parseCompilerOutput(r'C:\tmp\a.cpp:7: fatal error: foo.h: No such file or directory');
      expect(d.single.file, 'C:/tmp/a.cpp');
      expect(d.single.column, isNull);
      expect(d.single.message, 'foo.h: No such file or directory');
    });
  });

  test('BuildStatus fait un aller-retour en JSON', () {
    const status = BuildStatus(
      id: 'abc',
      state: BuildState.succeeded,
      board: 'esp32s3',
      log: 'ok',
      diagnostics: [Diagnostic(file: 'a.ino', line: 1, severity: DiagnosticSeverity.warning, message: 'w')],
      artifacts: [BuildArtifact(name: 'a.ino.merged.bin', role: ArtifactRole.merged, size: 10, sha256: 'ff')],
      durationMs: 1200,
    );
    final back = BuildStatus.fromJson(status.toJson());
    expect(back.state, BuildState.succeeded);
    expect(back.artifacts.single.role, ArtifactRole.merged);
    expect(back.diagnostics.single.message, 'w');
    expect(back.durationMs, 1200);
  });

  test('CompileBoard.fromId', () {
    expect(CompileBoard.fromId('esp32s3')!.fqbn, 'esp32:esp32:esp32s3');
    expect(CompileBoard.fromId('avr'), isNull);
  });
}

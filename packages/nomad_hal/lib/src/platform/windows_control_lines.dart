import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

typedef _GetPortHandleC = ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>);
typedef _GetPortHandle = int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>);
typedef _EscapeCommFunctionC = ffi.Int32 Function(ffi.IntPtr, ffi.Uint32);
typedef _EscapeCommFunction = int Function(int, int);

/// DTR/RTS rapides sous Windows via `EscapeCommFunction`, comme pyserial.
///
/// Passer par `sp_set_config` de libserialport coûte ~11 ms par ligne (un `SetCommState` complet).
/// La séquence d'auto-reset ESP traverse un état intermédiaire (DTR=1, RTS=1) qui ne doit pas
/// durer plus de quelques ms, sinon EN remonte avant qu'IO0 soit tiré à 0 et la carte démarre
/// normalement : le bootloader ne répond jamais.
class WindowsControlLines {
  WindowsControlLines._(this._handle, this._escape);

  static const int _setRts = 3;
  static const int _clrRts = 4;
  static const int _setDtr = 5;
  static const int _clrDtr = 6;

  final int _handle;
  final _EscapeCommFunction _escape;

  /// `null` si le HANDLE n'est pas récupérable : l'appelant retombe sur la config libserialport.
  static WindowsControlLines? tryCreate(SerialPort port) {
    try {
      final getHandle = ffi.DynamicLibrary.open('serialport.dll')
          .lookupFunction<_GetPortHandleC, _GetPortHandle>('sp_get_port_handle');
      final escape = ffi.DynamicLibrary.open('kernel32.dll')
          .lookupFunction<_EscapeCommFunctionC, _EscapeCommFunction>('EscapeCommFunction');
      final out = calloc<ffi.IntPtr>();
      try {
        final ok = getHandle(ffi.Pointer<ffi.Void>.fromAddress(port.address), out.cast());
        final handle = out.value;
        if (ok != 0 || handle == 0) return null;
        return WindowsControlLines._(handle, escape);
      } finally {
        calloc.free(out);
      }
    } catch (_) {
      return null;
    }
  }

  bool setDtr(bool on) => _escape(_handle, on ? _setDtr : _clrDtr) != 0;

  bool setRts(bool on) => _escape(_handle, on ? _setRts : _clrRts) != 0;
}

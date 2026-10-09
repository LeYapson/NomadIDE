// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'NomadMCU';

  @override
  String get navMonitor => 'Serial monitor';

  @override
  String get navMicroPython => 'MicroPython';

  @override
  String get navEditor => 'Editor';

  @override
  String get navSettings => 'Settings';

  @override
  String get settingsTitle => 'NomadMCU · Settings';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get languageSystem => 'System language';

  @override
  String get languageFrench => 'Français';

  @override
  String get languageEnglish => 'English';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonOk => 'OK';

  @override
  String get commonCreate => 'Create';

  @override
  String get commonRename => 'Rename';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonSave => 'Save';

  @override
  String get commonClose => 'Close';

  @override
  String get commonReplace => 'Replace';

  @override
  String bytesB(int count) {
    return '$count B';
  }

  @override
  String bytesKb(String value) {
    return '$value KB';
  }

  @override
  String bytesMb(String value) {
    return '$value MB';
  }

  @override
  String get monTitle => 'NomadMCU · Serial monitor';

  @override
  String get monStatusConnected => 'Connected';

  @override
  String get monStatusConnecting => 'Connecting…';

  @override
  String get monStatusDisconnected => 'Disconnected';

  @override
  String monTransportTooltip(String name) {
    return 'Transport: $name';
  }

  @override
  String get transportDesktop => 'Serial port (libserialport)';

  @override
  String get transportAndroidUsb => 'USB OTG (Android)';

  @override
  String get transportSimulated => 'Simulator';

  @override
  String get transportUnsupported => 'Not supported';

  @override
  String get monBoardLabel => 'Board';

  @override
  String get monNoBoardDetected => 'No board detected';

  @override
  String get monChooseBoard => 'Choose a board';

  @override
  String get monRefreshList => 'Refresh the list';

  @override
  String get monBaudLabel => 'Baud rate';

  @override
  String get monConnect => 'Connect';

  @override
  String get monConnecting => 'Connecting…';

  @override
  String get monDisconnect => 'Disconnect';

  @override
  String get monDtrTooltip => 'Data Terminal Ready';

  @override
  String get monRtsTooltip => 'Request To Send';

  @override
  String get monResetTooltip =>
      'Hardware reset via RTS (ESP32/ESP8266 boards with an auto-reset circuit)';

  @override
  String get monBootloader => 'Bootloader';

  @override
  String get monBootloaderTooltip =>
      'esptool sequence: restarts the ESP32 in download mode';

  @override
  String get monCtrlCTooltip => 'Interrupt the program (MicroPython)';

  @override
  String get monCtrlDTooltip => 'Soft reboot (MicroPython)';

  @override
  String get monHex => 'HEX';

  @override
  String get monHexTooltip => 'Show bytes in hexadecimal';

  @override
  String get monTimestamp => 'Timestamps';

  @override
  String get monClear => 'Clear';

  @override
  String monByteCounters(String rx, String tx) {
    return 'RX $rx · TX $tx';
  }

  @override
  String get monInputHintConnected => 'Command… (Enter to send, ↑/↓ history)';

  @override
  String get monInputHintDisconnected => 'Connect a board';

  @override
  String get monLineEndingTooltip => 'Line ending added when sending';

  @override
  String get monLineEndingNone => 'None';

  @override
  String get monSend => 'Send';

  @override
  String get monEmptyLog =>
      'Connect a board: the serial stream will appear here.';

  @override
  String monLogEnumerationFailed(String error) {
    return 'Could not list the ports: $error';
  }

  @override
  String monLogAttached(String name) {
    return 'Plugged in: $name';
  }

  @override
  String monLogDetached(String name) {
    return 'Unplugged: $name';
  }

  @override
  String monLogConnectedTo(String name, String config) {
    return 'Connected to $name ($config)';
  }

  @override
  String monLogConnectFailed(String error) {
    return 'Could not connect: $error';
  }

  @override
  String get monLogDisconnected => 'Disconnected.';

  @override
  String get monLogDeviceLost => 'The board was unplugged.';

  @override
  String get monLogConnectionError => 'Connection interrupted by an error.';

  @override
  String monLogBaud(String baud) {
    return 'Baud rate: $baud';
  }

  @override
  String get monLogReset => 'Hardware reset (RTS → EN pulse)';

  @override
  String get monLogBootloader =>
      'ESP bootloader sequence sent: the ROM is waiting for esptool';

  @override
  String get mpTitle => 'NomadMCU · MicroPython';

  @override
  String get mpTabConsole => 'Console';

  @override
  String get mpTabFiles => 'Files';

  @override
  String get mpConnectRawRepl => 'Connect (raw REPL)';

  @override
  String mpTransferLine(String arrow, String name, int done, int total) {
    return '$arrow $name · $done / $total B';
  }

  @override
  String get mpParentFolder => 'Parent folder';

  @override
  String get mpRefresh => 'Refresh';

  @override
  String get mpNewFile => 'New file';

  @override
  String get mpNewFolder => 'New folder';

  @override
  String get mpUploadFromProject => 'Send a project file to the board';

  @override
  String get mpSelfTest => 'Transfer test (speed and integrity)';

  @override
  String get mpFolderEmpty => 'Empty folder';

  @override
  String get mpNotConnected => 'Not connected';

  @override
  String get mpRunFile => 'Run this file';

  @override
  String get mpActions => 'Actions';

  @override
  String get mpMenuRename => 'Rename…';

  @override
  String get mpMenuDownload => 'Download to a project…';

  @override
  String get mpMenuDelete => 'Delete…';

  @override
  String get mpRenameOnBoardTitle => 'Rename on the board';

  @override
  String get mpNewName => 'New name';

  @override
  String get mpReplaceFileTitle => 'Replace the file?';

  @override
  String mpReplaceFileMessage(String name, String folder) {
    return '“$name” already exists in $folder on the board. It will be replaced.';
  }

  @override
  String get mpDownloadTitle => 'Download to a project';

  @override
  String get mpDownload => 'Download';

  @override
  String mpBinaryFile(int bytes) {
    return 'Binary file ($bytes bytes): no preview available.';
  }

  @override
  String get mpNameLabel => 'Name';

  @override
  String get mpContentLabel => 'Content';

  @override
  String get mpNewFileSample => 'print(\"test file\")\n';

  @override
  String get mpWriteToBoard => 'Write to the board';

  @override
  String mpDeleteTitle(String name) {
    return 'Delete $name?';
  }

  @override
  String get mpDeleteWarning => 'This cannot be undone.';

  @override
  String mpImageTitle(String name, int bytes) {
    return '$name ($bytes bytes)';
  }

  @override
  String get mpImageUnreadable => 'Unreadable image or unsupported format.';

  @override
  String get mpConsoleHint => 'MicroPython code (Ctrl+Enter to run)';

  @override
  String get mpStop => 'Stop';

  @override
  String get mpRun => 'Run';

  @override
  String get mpDefaultCode => 'print(\"Hello from NomadMCU\")';

  @override
  String get snippetMemory => 'memory';

  @override
  String get snippetError => 'error';

  @override
  String get snippetLoop => '3 s loop';

  @override
  String get snippetInfinite => 'infinite loop';

  @override
  String get qkTabTooltip => 'Insert an indentation';

  @override
  String qkInsert(String symbol) {
    return 'Insert $symbol';
  }

  @override
  String get qkCtrlCTooltip => 'Interrupt the running program';

  @override
  String get qkCtrlDTooltip => 'Restart the interpreter (soft reset)';

  @override
  String mpLogPortOpened(String name) {
    return 'Port opened: $name';
  }

  @override
  String get mpLogRawActive => 'Raw REPL active.';

  @override
  String get mpLogDone => 'Done.';

  @override
  String get mpLogDoneWithError => 'Done with an error.';

  @override
  String get mpLogSoftResetting => 'Soft reset…';

  @override
  String get mpLogSoftReset => 'Interpreter restarted.';

  @override
  String mpLogSelfTestStart(String kb) {
    return 'Transfer test: $kb KB, CRC32 checked by the board.';
  }

  @override
  String mpLogSelfTestRow(
      String chunk, String write, String read, String verdict) {
    return '· $chunk-byte chunks: write $write, read $read, $verdict';
  }

  @override
  String get mpSelfTestSame => 'readback identical ✓';

  @override
  String get mpSelfTestDiff => 'READBACK DIFFERENT ✗';

  @override
  String mpLogSelfTestFail(String chunk, String error) {
    return '· $chunk-byte chunks: FAILED ✗ $error';
  }

  @override
  String get mpLogSelfTestDone => 'Transfer test finished.';

  @override
  String mpRate(String kbps, String secs) {
    return '$kbps KB/s ($secs s)';
  }

  @override
  String mpLogRead(String path, int bytes) {
    return 'Read $path ($bytes bytes)';
  }

  @override
  String mpLogWritten(String path, int bytes) {
    return 'Written $path ($bytes bytes, CRC32 checked)';
  }

  @override
  String mpLogDeleted(String path) {
    return 'Deleted $path';
  }

  @override
  String mpLogRenamed(String from, String to) {
    return 'Renamed $from to $to';
  }

  @override
  String mpLogLocalReadFailed(String name) {
    return 'Could not read the local file: “$name”';
  }

  @override
  String mpLogDownloadCorrupt(String received, String expected) {
    return 'Corrupted download: $received bytes received, $expected expected.';
  }

  @override
  String mpLogLocalSaveFailed(String name) {
    return 'Could not save locally: “$name”';
  }

  @override
  String mpLogDownloaded(String from, String to, int bytes) {
    return 'Downloaded $from to $to ($bytes bytes, CRC32 checked)';
  }

  @override
  String mpLogFolderCreated(String path) {
    return 'Folder created $path';
  }

  @override
  String get mpLogResync => 'Session out of sync, retrying…';

  @override
  String get mpLogResynced => 'Session restored.';

  @override
  String mpLogResyncFailed(String error) {
    return 'Could not resynchronize: $error';
  }

  @override
  String get edTitle => 'NomadMCU · Editor';

  @override
  String get edDraftsTitle => 'Resume your unsaved work?';

  @override
  String get edDraftsIntro => 'The app closed before these files were saved:';

  @override
  String edDraftItem(String name) {
    return '• $name';
  }

  @override
  String edDraftItemProject(String name, String project) {
    return '• $name  ($project)';
  }

  @override
  String get edDraftsDiscard => 'Discard';

  @override
  String get edDraftsRestore => 'Restore';

  @override
  String edReplaceFileMessage(String path, String project) {
    return '“$path” already exists in the project “$project”. Its content will be replaced.';
  }

  @override
  String get edSendTitle => 'Send to the board';

  @override
  String get edSendPathLabel => 'Path on the board';

  @override
  String get edSendHelper => 'E.g. /main.py (runs when the board starts)';

  @override
  String get edSend => 'Send';

  @override
  String edSentSnack(String path) {
    return 'Sent to the board: $path (CRC32 checked)';
  }

  @override
  String edCloseTitle(String name) {
    return 'Save “$name”?';
  }

  @override
  String get edCloseBody => 'This file has unsaved changes.';

  @override
  String get edDontSave => 'Don’t save';

  @override
  String get edSaveTooltip => 'Save on this device (Ctrl+S)';

  @override
  String get edSendTooltip => 'Send to the board';

  @override
  String get edConnectBoardHint => 'Connect a board (MicroPython tab)';

  @override
  String get edRunTooltip =>
      'Run the selection or the file on the board (without saving)';

  @override
  String get edHideOutput => 'Hide the output';

  @override
  String get edShowOutput => 'Show the output';

  @override
  String get edEmptyTitle => 'No file open.';

  @override
  String get edEmptyBody =>
      'Create a file, open one from your projects (menu at the top left), or tap a file on the board in the MicroPython tab.';

  @override
  String edRunLabelSelection(String name) {
    return 'run $name (selection)';
  }

  @override
  String get prNoProjects => 'No projects.';

  @override
  String get prLoading => 'Loading…';

  @override
  String get prNewProject => 'New project';

  @override
  String get prProjectEmpty => 'Empty project';

  @override
  String get prProjectNameLabel => 'Project name';

  @override
  String get prDefaultProjectName => 'My project';

  @override
  String get prProjects => 'Projects';

  @override
  String get prProjectActions => 'Project actions';

  @override
  String get prMenuNewProject => 'New project…';

  @override
  String get prMenuRenameProject => 'Rename the project…';

  @override
  String get prMenuDeleteProject => 'Delete the project…';

  @override
  String get prRenameProjectTitle => 'Rename the project';

  @override
  String get prDeleteProjectTitle => 'Delete the project?';

  @override
  String prDeleteProjectMessage(String name) {
    return 'The project “$name” and all its files will be deleted from this device. This cannot be undone.';
  }

  @override
  String get prFileNameLabel => 'File name';

  @override
  String get prFolderNameLabel => 'Folder name';

  @override
  String get prMenuUpload => 'Send to the board';

  @override
  String get prMenuUploadDisconnected =>
      'Send to the board (no board connected)';

  @override
  String get prDeleteFolderTitle => 'Delete the folder?';

  @override
  String get prDeleteFileTitle => 'Delete the file?';

  @override
  String prDeleteFolderMessage(String name) {
    return '“$name” and all its content will be deleted from this device.';
  }

  @override
  String prDeleteFileMessage(String name) {
    return '“$name” will be deleted from this device.';
  }

  @override
  String get sdSaveTitle => 'Save on this device';

  @override
  String get sdProject => 'Project';

  @override
  String get sdNewProjectItem => 'New project…';

  @override
  String get sdNewProjectName => 'New project name';

  @override
  String get sdFileLabel => 'File';

  @override
  String get sdFileHelper => 'E.g. main.py or lib/sensor.py';

  @override
  String get pfTitle => 'Choose a file to send';

  @override
  String get pfNoProject => 'No projects';

  @override
  String get pfNothing => 'Nothing here';

  @override
  String get navFlash => 'Flash';

  @override
  String get flashTitle => 'NomadMCU · Flash a program';

  @override
  String get flashUnsupported =>
      'Copying a .uf2 file is not yet possible on this system (Android: planned through the PICOBOOT protocol).';

  @override
  String get flashStepFile => '1. Program file';

  @override
  String get flashPickFile => 'Choose a .uf2 file';

  @override
  String get flashNoFile => 'No file chosen';

  @override
  String flashFileInfo(String family, String amount, int blocks) {
    return '$family · $amount · $blocks blocks';
  }

  @override
  String get flashFamilyUnknown => 'family not specified';

  @override
  String get flashStepBoard => '2. Board';

  @override
  String get flashBoardHint =>
      'The board restarts into BOOTSEL by itself. Otherwise: hold the BOOTSEL button, plug in the USB cable, then release.';

  @override
  String flashDriveFound(String drive, String board) {
    return 'BOOTSEL drive found: $drive ($board)';
  }

  @override
  String get flashDriveNone => 'No BOOTSEL drive detected yet.';

  @override
  String get flashStepRun => '3. Writing';

  @override
  String get flashRun => 'Flash';

  @override
  String get flashPhaseTouching => 'Restarting the board into BOOTSEL mode…';

  @override
  String get flashPhaseWaiting => 'Waiting for the BOOTSEL drive…';

  @override
  String flashPhaseCopying(int percent) {
    return 'Copying to the board… $percent%';
  }

  @override
  String get flashPhaseRebooting => 'Waiting for the board to restart…';

  @override
  String flashDone(String amount) {
    return 'Program written ($amount). The board restarted and is running the new program.';
  }

  @override
  String get flashNoReboot =>
      'The file was copied but the board did not restart: it probably refused the program (wrong chip?). Check that the file is made for this board.';

  @override
  String get flashNoDrive =>
      'No BOOTSEL drive appeared. Hold the BOOTSEL button, plug in the USB cable, then release, and try again.';

  @override
  String flashCopyFailed(int done, int total, String cause) {
    return 'Copy interrupted at $done of $total bytes ($cause). The board may hold an incomplete program: unplug it, hold BOOTSEL while plugging it back in, then try again.';
  }

  @override
  String flashBadFile(String reason) {
    return 'Invalid UF2 file: $reason';
  }

  @override
  String flashWrongFamily(String family) {
    return 'This file is made for a different chip ($family) than this Raspberry Pi RP2 board.';
  }

  @override
  String flashReadFailed(String cause) {
    return 'Could not read the file: $cause';
  }

  @override
  String get errSerialUnsupportedIos =>
      'iOS does not allow access to USB-serial adapters: there is no public USB Host API, only MFi-certified accessories are reachable. Use the simulated mode, and later the BLE or WebREPL transports.';

  @override
  String errSerialUnsupportedPlatform(String platform) {
    return 'Unsupported platform: $platform.';
  }

  @override
  String errDeviceNotFound(String device) {
    return '$device is no longer connected.';
  }

  @override
  String errPortNotFound(String path) {
    return 'Port $path not found.';
  }

  @override
  String get errUsbPermissionDenied =>
      'USB permission denied, or USB-serial chip not supported.';

  @override
  String errPortPermissionDenied(String path, String os) {
    return 'Could not open $path: $os. Add your user to the “dialout” group (Debian/Ubuntu) or “uucp” (Arch), then log in again.';
  }

  @override
  String errOpenFailedPath(String path, String os) {
    return 'Could not open $path: $os. The port may be in use by another application (Arduino IDE, Thonny…).';
  }

  @override
  String errOpenFailedDevice(String device) {
    return 'Could not open $device.';
  }

  @override
  String get errUnknownOsError => 'unknown error';

  @override
  String get errUsbPortCreateFailed => 'Could not create the USB port.';

  @override
  String get errUsbStreamUnavailable => 'USB receive stream unavailable.';

  @override
  String errAlreadyOpen(String device) {
    return '$device is already open.';
  }

  @override
  String get errConnectionClosed => 'The connection is closed.';

  @override
  String get errClosedDuringRead => 'The port was closed while reading.';

  @override
  String get errReadFailed => 'Serial port read error.';

  @override
  String errNoResponse(int timeoutMs) {
    return 'No response from the board after $timeoutMs ms.';
  }

  @override
  String errOperationWrite(String device) {
    return 'Could not write to $device.';
  }

  @override
  String errOperationConfigure(String device) {
    return 'Could not configure $device.';
  }

  @override
  String errOperationDtr(String device) {
    return 'Could not drive DTR on $device.';
  }

  @override
  String errOperationRts(String device) {
    return 'Could not drive RTS on $device.';
  }

  @override
  String get errUnsupportedStopBits =>
      '1.5 stop bits are not supported by libserialport.';

  @override
  String errWriteTimeout(int remaining, int seconds) {
    return 'Write interrupted: $remaining bytes not sent after $seconds s.';
  }

  @override
  String errSerialOther(String message) {
    return 'Serial error: $message';
  }

  @override
  String get errLinkReadFailed => 'Link read error.';

  @override
  String get errLinkClosed => 'The link was closed.';

  @override
  String errRawReplNotEntered(int attempts) {
    return 'The board does not enter raw REPL after $attempts attempts. Check that it is a MicroPython board and that the port is not in use elsewhere.';
  }

  @override
  String errProgramTimeout(int timeoutMs) {
    return 'The program exceeded $timeoutMs ms and was interrupted.';
  }

  @override
  String get errBusy => 'A run is already in progress.';

  @override
  String get errNotActive => 'Raw REPL inactive: connect first.';

  @override
  String get errSessionBroken =>
      'Session out of sync: reconnect to restore it.';

  @override
  String errUnexpectedAck(String hex) {
    return 'Unexpected reply instead of “OK”: $hex.';
  }

  @override
  String errUnexpectedCrcReply(String reply) {
    return 'Unexpected reply to the CRC computation: “$reply”.';
  }

  @override
  String errIntegrity(String path, int expectedSize, int actualSize) {
    return 'Corrupted transfer on $path: expected $expectedSize bytes, got $actualSize.';
  }

  @override
  String errProtocolOther(String message) {
    return 'Protocol error: $message';
  }

  @override
  String errStorageInvalidName(String name) {
    return 'Invalid name $name. Avoid the characters / \\ : * ? \" < > | and reserved names (CON, NUL…).';
  }

  @override
  String errStorageAlreadyExists(String name) {
    return '$name already exists.';
  }

  @override
  String errStorageNotFound(String name) {
    return '$name was not found.';
  }

  @override
  String errStorageOutsideProject(String name) {
    return 'Path refused $name: it would leave the project.';
  }

  @override
  String errStorageIo(String name, String cause) {
    return 'Storage error $name: $cause.';
  }

  @override
  String errEspSyncFailed(int attempts) {
    return 'The ESP bootloader does not answer ($attempts attempts). Check the cable, then hold the BOOT button while briefly pressing EN (RESET).';
  }

  @override
  String errEspRom(String command, String error) {
    return 'The ESP bootloader refused command 0x$command (error 0x$error).';
  }

  @override
  String errEspBadPacket(String hex) {
    return 'Unreadable answer from the ESP bootloader: $hex';
  }

  @override
  String errEspVerifyFailed(String expected, String actual) {
    return 'The flash does not match the file that was sent (expected MD5 $expected, read $actual). Try again; if it happens again, check the cable.';
  }
}

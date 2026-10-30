import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef FindWindowNative = IntPtr Function(Pointer<Utf16> lpClassName, Pointer<Utf16> lpWindowName);
typedef FindWindowDart = int Function(Pointer<Utf16> lpClassName, Pointer<Utf16> lpWindowName);

typedef ShowWindowNative = Int32 Function(IntPtr hWnd, Int32 nCmdShow);
typedef ShowWindowDart = int Function(int hWnd, int nCmdShow);

typedef SetForegroundWindowNative = Int32 Function(IntPtr hWnd);
typedef SetForegroundWindowDart = int Function(int hWnd);

class WindowService {
  static const int swHide = 0;
  static const int swShow = 5;
  static const int swRestore = 9;

  static DynamicLibrary? _user32;
  static FindWindowDart? _findWindow;
  static ShowWindowDart? _showWindow;
  static SetForegroundWindowDart? _setForegroundWindow;
  static bool _initialized = false;

  static void _ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    if (!Platform.isWindows) return;

    try {
      _user32 = DynamicLibrary.open('user32.dll');
      _findWindow = _user32!.lookupFunction<FindWindowNative, FindWindowDart>('FindWindowW');
      _showWindow = _user32!.lookupFunction<ShowWindowNative, ShowWindowDart>('ShowWindow');
      _setForegroundWindow =
          _user32!.lookupFunction<SetForegroundWindowNative, SetForegroundWindowDart>('SetForegroundWindow');
    } catch (_) {}
  }

  static int _getHwnd() {
    _ensureInitialized();
    if (_findWindow == null) return 0;
    final titlePtr = 'Mirroring'.toNativeUtf16();
    try {
      return _findWindow!(nullptr, titlePtr);
    } catch (_) {
      return 0;
    } finally {
      calloc.free(titlePtr);
    }
  }

  /// Hides the main Flutter application window.
  static Future<void> hide() async {
    _ensureInitialized();
    final hwnd = _getHwnd();
    if (hwnd != 0 && _showWindow != null) {
      _showWindow!(hwnd, swHide);
    }
  }

  /// Restores and brings the main Flutter application window to the foreground.
  static Future<void> show() async {
    _ensureInitialized();
    final hwnd = _getHwnd();
    if (hwnd != 0 && _showWindow != null) {
      _showWindow!(hwnd, swRestore);
      _showWindow!(hwnd, swShow);
      _setForegroundWindow?.call(hwnd);
    }
  }
}

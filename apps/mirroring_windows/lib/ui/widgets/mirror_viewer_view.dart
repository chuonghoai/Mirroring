import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mirroring_protocol/mirroring_protocol.dart';
import '../controllers/lan_mirroring_controller.dart';

class MirrorViewerView extends StatefulWidget {
  final LanMirroringController controller;

  const MirrorViewerView({super.key, required this.controller});

  @override
  State<MirrorViewerView> createState() => _MirrorViewerViewState();
}

class _MirrorViewerViewState extends State<MirrorViewerView> {
  final FocusNode _viewerFocusNode = FocusNode();
  final FocusNode _textFocusNode = FocusNode();
  final TextEditingController _textInputController = TextEditingController();

  final List<Offset> _activeStrokePoints = [];
  DateTime? _strokeStartTime;
  Offset? _strokeStartLocal;
  int? _activePointerId;
  bool _isPrimaryDown = false;

  Offset? _tapFeedbackNormalized;
  Timer? _tapFeedbackTimer;

  @override
  void dispose() {
    _tapFeedbackTimer?.cancel();
    _viewerFocusNode.dispose();
    _textFocusNode.dispose();
    _textInputController.dispose();
    super.dispose();
  }

  Offset _normalize(Offset local, Size size) {
    final x = (local.dx / size.width).clamp(0.0, 1.0);
    final y = (local.dy / size.height).clamp(0.0, 1.0);
    return Offset(x, y);
  }

  void _showTapIndicator(Offset normalized) {
    _tapFeedbackTimer?.cancel();
    setState(() {
      _tapFeedbackNormalized = normalized;
    });
    _tapFeedbackTimer = Timer(const Duration(milliseconds: 220), () {
      if (mounted) {
        setState(() {
          _tapFeedbackNormalized = null;
        });
      }
    });
  }

  void _onPointerDown(PointerDownEvent event, Size size) {
    if (!_textFocusNode.hasFocus) {
      _viewerFocusNode.requestFocus();
    }

    if (event.buttons == kSecondaryMouseButton) {
      widget.controller.sendInputAction('back');
      return;
    }
    if (event.buttons == kMiddleMouseButton) {
      widget.controller.sendInputAction('home');
      return;
    }
    if ((event.buttons & kPrimaryMouseButton) == 0) {
      return;
    }

    _activePointerId = event.pointer;
    _isPrimaryDown = true;
    _strokeStartTime = DateTime.now();
    _strokeStartLocal = event.localPosition;
    _activeStrokePoints
      ..clear()
      ..add(_normalize(event.localPosition, size));
  }

  void _onPointerMove(PointerMoveEvent event, Size size) {
    if (!_isPrimaryDown || event.pointer != _activePointerId) return;
    final norm = _normalize(event.localPosition, size);
    if (_activeStrokePoints.isNotEmpty) {
      final last = _activeStrokePoints.last;
      if ((norm - last).distance < 0.008) return;
    }
    if (_activeStrokePoints.length < 28) {
      _activeStrokePoints.add(norm);
    }
  }

  void _onPointerUp(PointerUpEvent event, Size size) {
    if (!_isPrimaryDown || event.pointer != _activePointerId) return;
    _isPrimaryDown = false;
    _activePointerId = null;

    final endNorm = _normalize(event.localPosition, size);
    final startLocal = _strokeStartLocal ?? event.localPosition;
    final elapsedMs = _strokeStartTime != null
        ? DateTime.now().difference(_strokeStartTime!).inMilliseconds
        : 45;
    final moveDistPx = (event.localPosition - startLocal).distance;

    if (moveDistPx < 10.0) {
      // Tap or Long-Press
      final durationMs = elapsedMs >= 380 ? math.min(elapsedMs, 1100) : 45;
      widget.controller.sendTouchGesture(
        points: [
          {'x': endNorm.dx, 'y': endNorm.dy},
        ],
        durationMs: durationMs,
      );
      _showTapIndicator(endNorm);
    } else {
      _activeStrokePoints.add(endNorm);
      final durationMs = elapsedMs.clamp(70, 1100);
      widget.controller.sendTouchGesture(
        points: _activeStrokePoints
            .map((p) => {'x': p.dx, 'y': p.dy})
            .toList(),
        durationMs: durationMs,
      );
      _showTapIndicator(endNorm);
    }
    _activeStrokePoints.clear();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer == _activePointerId) {
      _isPrimaryDown = false;
      _activePointerId = null;
      _activeStrokePoints.clear();
    }
  }

  void _onPointerSignal(PointerSignalEvent event, Size size) {
    if (event is PointerScrollEvent) {
      final center = _normalize(event.localPosition, size);
      // Mouse wheel down (positive dy) -> swipe finger upward to scroll down
      final deltaY = event.scrollDelta.dy > 0 ? -0.22 : 0.22;
      final startY = (center.dy - deltaY * 0.5).clamp(0.05, 0.95);
      final endY = (center.dy + deltaY * 0.5).clamp(0.05, 0.95);
      widget.controller.sendTouchGesture(
        points: [
          {'x': center.dx, 'y': startY},
          {'x': center.dx, 'y': endY},
        ],
        durationMs: 180,
      );
    }
  }

  KeyEventResult _handleViewerKeyEvent(FocusNode node, KeyEvent event) {
    if (_textFocusNode.hasFocus) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyV) {
      widget.controller.pushClipboardToPhone();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.controller.sendInputAction('back');
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      widget.controller.sendInputAction('backspace');
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      widget.controller.sendInputAction('enter');
      return KeyEventResult.handled;
    }

    final ch = event.character;
    if (ch != null && ch.isNotEmpty && !isCtrl) {
      final code = ch.codeUnitAt(0);
      if (code >= 32 && code != 127) {
        widget.controller.sendInputText(ch);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _submitQuickText() {
    final text = _textInputController.text;
    if (text.isEmpty) {
      widget.controller.sendInputAction('enter');
      return;
    }
    widget.controller.sendInputText(text);
    _textInputController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final device = widget.controller.activeDevice;
        final textureId = widget.controller.textureId;
        final w = widget.controller.streamWidth;
        final h = widget.controller.streamHeight;
        final aspectRatio = (w > 0 && h > 0) ? w / h : (9.0 / 16.0);
        final isStreaming =
            widget.controller.sessionStatus == WindowsDeviceStatus.streaming;

        return Focus(
          focusNode: _viewerFocusNode,
          autofocus: true,
          onKeyEvent: _handleViewerKeyEvent,
          child: Scaffold(
            backgroundColor: const Color(0xFF020617),
            body: Column(
              children: [
                // Top viewer toolbar
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0F172A),
                    border: Border(
                      bottom: BorderSide(color: Color(0xFF1E293B)),
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Đóng màn hình & quay lại trình điều khiển',
                        onPressed: widget.controller.stopSession,
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Color(0xFFCBD5E1), size: 19),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              device?.deviceName ?? 'Android Screen',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              isStreaming && w > 0 && h > 0
                                  ? '$w×$h • ${widget.controller.fps} FPS • LAN'
                                  : (widget.controller.statusMessage ??
                                      'Đang chờ khung hình...'),
                              style: const TextStyle(
                                color: Color(0xFF34D399),
                                fontSize: 11,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Tooltip(
                        message:
                            'Gửi Clipboard Windows sang Android (Ctrl+V)',
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final ok =
                                await widget.controller.pushClipboardToPhone();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: ok
                                      ? const Color(0xFF065F46)
                                      : const Color(0xFF78350F),
                                  content: Text(
                                    widget.controller.statusMessage ?? '',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.content_paste_go_rounded,
                              size: 14),
                          label: const Text('Clipboard',
                              style: TextStyle(fontSize: 11.5)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF38BDF8),
                            side: const BorderSide(color: Color(0xFF334155)),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 6,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton.icon(
                        onPressed: widget.controller.stopSession,
                        icon: const Icon(Icons.stop_circle_outlined, size: 15),
                        label:
                            const Text('Dừng', style: TextStyle(fontSize: 11.5)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                if (!widget.controller.accessibilityEnabled)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    color: const Color(0xFF78350F).withValues(alpha: 0.7),
                    child: const Row(
                      children: [
                        Icon(Icons.accessibility_new_rounded,
                            color: Color(0xFFFBBF24), size: 15),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Bật "Mirroring Remote Control" trong Cài đặt Trợ năng (Accessibility) trên điện thoại để điều khiển chuột & bàn phím.',
                            style: TextStyle(
                              color: Color(0xFFFEF3C7),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Interactive Video Surface
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: textureId != null && w > 0 && h > 0
                          ? AspectRatio(
                              aspectRatio: aspectRatio,
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final size = constraints.biggest;
                                  return MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: Listener(
                                      behavior: HitTestBehavior.opaque,
                                      onPointerDown: (e) =>
                                          _onPointerDown(e, size),
                                      onPointerMove: (e) =>
                                          _onPointerMove(e, size),
                                      onPointerUp: (e) => _onPointerUp(e, size),
                                      onPointerCancel: _onPointerCancel,
                                      onPointerSignal: (e) =>
                                          _onPointerSignal(e, size),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            child: Texture(
                                              textureId: textureId,
                                              filterQuality:
                                                  FilterQuality.medium,
                                            ),
                                          ),
                                          if (_tapFeedbackNormalized != null)
                                            Positioned(
                                              left: _tapFeedbackNormalized!.dx *
                                                      size.width -
                                                  12,
                                              top: _tapFeedbackNormalized!.dy *
                                                      size.height -
                                                  12,
                                              child: IgnorePointer(
                                                child: Container(
                                                  width: 24,
                                                  height: 24,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: const Color(0xFF38BDF8)
                                                        .withValues(alpha: 0.3),
                                                    border: Border.all(
                                                      color: const Color(
                                                          0xFF38BDF8),
                                                      width: 1.5,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            )
                          : const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                  color: Color(0xFF38BDF8),
                                ),
                                SizedBox(height: 14),
                                Text(
                                  'Đang giải mã luồng video H.264 từ điện thoại...',
                                  style: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),

                // Bottom Navigation & IME Text Bar
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0F172A),
                    border: Border(
                      top: BorderSide(color: Color(0xFF1E293B)),
                    ),
                  ),
                  child: Row(
                    children: [
                      _navButton(
                        tooltip: 'Quay lại (Chuột phải / Esc)',
                        icon: Icons.arrow_back_ios_new_rounded,
                        onTap: () => widget.controller.sendInputAction('back'),
                      ),
                      const SizedBox(width: 4),
                      _navButton(
                        tooltip: 'Màn hình chính (Chuột giữa)',
                        icon: Icons.radio_button_unchecked_rounded,
                        onTap: () => widget.controller.sendInputAction('home'),
                      ),
                      const SizedBox(width: 4),
                      _navButton(
                        tooltip: 'Đa nhiệm (Recents)',
                        icon: Icons.crop_square_rounded,
                        onTap: () =>
                            widget.controller.sendInputAction('recents'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 32,
                          child: TextField(
                            focusNode: _textFocusNode,
                            controller: _textInputController,
                            onSubmitted: (_) => _submitQuickText(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Gõ chữ tiếng Việt / Enter để gửi...',
                              hintStyle: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 11.5,
                              ),
                              filled: true,
                              fillColor: const Color(0xFF1E293B),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 0,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                    color: Color(0xFF334155)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                    color: Color(0xFF3B82F6)),
                              ),
                              suffixIcon: IconButton(
                                padding: EdgeInsets.zero,
                                tooltip: 'Gửi văn bản',
                                icon: const Icon(Icons.send_rounded,
                                    size: 15, color: Color(0xFF38BDF8)),
                                onPressed: _submitQuickText,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _navButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Icon(icon, size: 15, color: const Color(0xFFCBD5E1)),
        ),
      ),
    );
  }
}

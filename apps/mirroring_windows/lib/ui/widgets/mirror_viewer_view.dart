import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mirroring_protocol/mirroring_protocol.dart';
import '../controllers/lan_mirroring_controller.dart';

class MirrorViewerView extends StatelessWidget {
  final LanMirroringController controller;

  const MirrorViewerView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final device = controller.activeDevice;
        final textureId = controller.textureId;
        final w = controller.streamWidth;
        final h = controller.streamHeight;
        final aspectRatio = (w > 0 && h > 0) ? w / h : (9.0 / 16.0);
        final isStreaming =
            controller.sessionStatus == WindowsDeviceStatus.streaming;

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyV, control: true): () {
              controller.pushClipboardToPhone();
            },
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              backgroundColor: const Color(0xFF020617),
              body: Column(
                children: [
                  // Top viewer toolbar
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0F172A),
                      border: Border(
                        bottom: BorderSide(color: Color(0xFF1E293B)),
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Quay lại danh sách thiết bị',
                          onPressed: controller.hideViewerToDeviceList,
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
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                isStreaming && w > 0 && h > 0
                                    ? '$w×$h • ${controller.fps} FPS • LAN'
                                    : (controller.statusMessage ??
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
                                  await controller.pushClipboardToPhone();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: ok
                                        ? const Color(0xFF065F46)
                                        : const Color(0xFF78350F),
                                    content: Text(
                                      controller.statusMessage ?? '',
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
                                size: 15),
                            label: const Text('Gửi Clipboard',
                                style: TextStyle(fontSize: 11.5)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF38BDF8),
                              side: const BorderSide(color: Color(0xFF334155)),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: controller.stopSession,
                          icon: const Icon(Icons.stop_circle_outlined, size: 16),
                          label: const Text('Dừng',
                              style: TextStyle(fontSize: 11.5)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Video Surface
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: textureId != null && w > 0 && h > 0
                            ? AspectRatio(
                                aspectRatio: aspectRatio,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Texture(
                                    textureId: textureId,
                                    filterQuality: FilterQuality.medium,
                                  ),
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
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

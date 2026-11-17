import 'package:flutter/material.dart';
import 'package:mirroring_protocol/mirroring_protocol.dart';
import '../controllers/lan_mirroring_controller.dart';

class LanMirroringView extends StatelessWidget {
  final LanMirroringController controller;

  const LanMirroringView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final devices = controller.devices;
        final activeId = controller.activeDeviceId;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Discovery Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'THIẾT BỊ ANDROID TRONG LAN',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: controller.refreshDiscovery,
                        borderRadius: BorderRadius.circular(8),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.refresh_rounded,
                                  size: 14, color: Color(0xFF38BDF8)),
                              SizedBox(width: 4),
                              Text(
                                'Quét lại',
                                style: TextStyle(
                                  color: Color(0xFF38BDF8),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (devices.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 18,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: const Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF38BDF8),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Đang tìm điện thoại mở ứng dụng Mirroring cùng mạng Wi-Fi / LAN...',
                              style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 12.5,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ...devices.map(
                      (device) => _buildDeviceTile(
                        device: device,
                        isCurrentTarget: device.deviceId == activeId,
                      ),
                    ),
                ],
              ),
            ),

            if (controller.statusMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: Color(0xFF38BDF8), size: 17),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        controller.statusMessage!,
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (controller.errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF450A0A).withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: Color(0xFFF87171), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        controller.errorMessage!,
                        style: const TextStyle(
                          color: Color(0xFFFECACA),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF334155).withValues(alpha: 0.6),
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.wifi_tethering_rounded,
                      color: Color(0xFF38BDF8), size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Chế độ LAN không cần USB, không cần ADB hay Wireless Debugging. Mở ứng dụng Mirroring trên Android cùng Wi-Fi rồi bấm Kết nối.',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDeviceTile({
    required DiscoveredDevice device,
    required bool isCurrentTarget,
  }) {
    final effectiveStatus =
        isCurrentTarget ? controller.sessionStatus : device.status;
    final (badgeText, badgeColor, badgeBg) = _statusStyle(effectiveStatus);

    final isPendingApproval = isCurrentTarget &&
        (effectiveStatus == WindowsDeviceStatus.connectionRequested ||
            effectiveStatus == WindowsDeviceStatus.waitingForApproval ||
            effectiveStatus == WindowsDeviceStatus.connecting);

    final isActiveStream = isCurrentTarget &&
        (effectiveStatus == WindowsDeviceStatus.streaming ||
            effectiveStatus == WindowsDeviceStatus.connected);

    final canConnect = !controller.isBusyConnecting &&
        !controller.isStreamingOrConnected &&
        device.availability == DeviceAvailability.available;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActiveStream
              ? const Color(0xFF10B981)
              : (isPendingApproval
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFF334155)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.smartphone_rounded,
                    color: Color(0xFF60A5FA), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.deviceName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${device.ipAddress}:${device.controlPort} • ID ${device.shortId}',
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBg.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.45)),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (isPendingApproval) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: controller.cancelPendingRequest,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Hủy yêu cầu'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFBBF24),
                      side: const BorderSide(color: Color(0xFFF59E0B)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ] else if (isActiveStream) ...[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: controller.showViewer,
                    icon: const Icon(Icons.tv_rounded, size: 16),
                    label: const Text('Mở màn hình'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: controller.stopSession,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFF87171),
                    side: const BorderSide(color: Color(0xFFEF4444)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Ngắt'),
                ),
              ] else ...[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        canConnect ? () => controller.connectToDevice(device) : null,
                    icon: const Icon(Icons.cast_connected_rounded, size: 16),
                    label: Text(
                      device.availability == DeviceAvailability.available
                          ? 'Kết nối & Chiếu màn hình'
                          : 'Thiết bị đang bận',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      disabledBackgroundColor: const Color(0xFF334155),
                      disabledForegroundColor: const Color(0xFF64748B),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  (String, Color, Color) _statusStyle(WindowsDeviceStatus status) {
    switch (status) {
      case WindowsDeviceStatus.available:
        return ('Sẵn sàng', const Color(0xFF34D399), const Color(0xFF065F46));
      case WindowsDeviceStatus.connectionRequested:
        return ('Đã gửi yêu cầu', const Color(0xFF38BDF8), const Color(0xFF0C4A6E));
      case WindowsDeviceStatus.waitingForApproval:
        return ('Chờ xác nhận', const Color(0xFFFBBF24), const Color(0xFF78350F));
      case WindowsDeviceStatus.connecting:
        return ('Đang kết nối', const Color(0xFF38BDF8), const Color(0xFF0C4A6E));
      case WindowsDeviceStatus.connected:
        return ('Đã kết nối', const Color(0xFF34D399), const Color(0xFF065F46));
      case WindowsDeviceStatus.streaming:
        return ('Đang trình chiếu', const Color(0xFF34D399), const Color(0xFF065F46));
      case WindowsDeviceStatus.disconnected:
        return ('Đã ngắt kết nối', const Color(0xFF94A3B8), const Color(0xFF334155));
      case WindowsDeviceStatus.unavailable:
        return ('Không khả dụng', const Color(0xFFFBBF24), const Color(0xFF78350F));
      case WindowsDeviceStatus.connectionFailed:
        return ('Kết nối thất bại', const Color(0xFFF87171), const Color(0xFF7F1D1D));
    }
  }
}

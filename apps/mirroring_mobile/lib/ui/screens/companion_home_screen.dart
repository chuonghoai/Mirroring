import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/models/companion_state.dart';
import '../controllers/companion_controller.dart';

class CompanionHomeScreen extends StatefulWidget {
  final CompanionController controller;

  const CompanionHomeScreen({super.key, required this.controller});

  @override
  State<CompanionHomeScreen> createState() => _CompanionHomeScreenState();
}

class _CompanionHomeScreenState extends State<CompanionHomeScreen> {
  String? _appVersion;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final content = await rootBundle.loadString('pubspec.yaml');
      final match = RegExp(r'^version:\s*([^\s+]+)', multiLine: true).firstMatch(content);
      if (match != null && mounted) {
        setState(() {
          _appVersion = match.group(1);
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        final logs = widget.controller.logs;

        return Scaffold(
          backgroundColor: const Color(0xFF0F172A),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: widget.controller.refreshDiscovery,
              color: const Color(0xFF38BDF8),
              backgroundColor: const Color(0xFF1E293B),
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                children: [
                  _buildHeader(state),
                  const SizedBox(height: 16),

                  if (!state.hasNotificationPermission) ...[
                    _buildNotificationPermissionBanner(),
                    const SizedBox(height: 14),
                  ],

                  if (state.pendingRequest != null) ...[
                    _buildIncomingRequestCard(state, state.pendingRequest!),
                    const SizedBox(height: 14),
                  ],

                  if (state.isActiveSession) ...[
                    _buildActiveSessionCard(state),
                    const SizedBox(height: 14),
                  ],

                  _buildDeviceIdentityCard(state),
                  const SizedBox(height: 14),

                  _buildDiscoveredHostsCard(state),
                  const SizedBox(height: 14),

                  if (state.statusMessage != null && state.statusMessage!.isNotEmpty) ...[
                    _buildStatusBanner(state.statusMessage!),
                    const SizedBox(height: 14),
                  ],

                  if (logs.isNotEmpty) ...[
                    _buildLogsCard(logs),
                    const SizedBox(height: 14),
                  ],

                  _buildFooter(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(CompanionAppState state) {
    final (label, color, bg) = switch (state.sessionStatus) {
      CompanionSessionStatus.idle => (
          'Sẵn sàng',
          const Color(0xFF34D399),
          const Color(0xFF065F46),
        ),
      CompanionSessionStatus.pendingApproval => (
          'Chờ xác nhận',
          const Color(0xFFFBBF24),
          const Color(0xFF78350F),
        ),
      CompanionSessionStatus.awaitingCapturePermission => (
          'Cấp quyền màn hình',
          const Color(0xFF38BDF8),
          const Color(0xFF0C4A6E),
        ),
      CompanionSessionStatus.streaming => (
          'Đang trình chiếu',
          const Color(0xFF34D399),
          const Color(0xFF065F46),
        ),
      CompanionSessionStatus.reconnecting => (
          'Đang kết nối lại',
          const Color(0xFFFBBF24),
          const Color(0xFF78350F),
        ),
    };

    return Row(
      children: [
        Image.asset(
          'assets/app_icon.jpg',
          width: 40,
          height: 40,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.cast_rounded, color: Color(0xFF60A5FA)),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mirroring',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'Android Companion • LAN Không dây',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: bg.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNotificationPermissionBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF78350F).withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_active_rounded, color: Color(0xFFFBBF24), size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Cần quyền thông báo để hiển thị trạng thái Foreground Service khi chia sẻ màn hình dưới nền.',
              style: TextStyle(color: Color(0xFFFEF3C7), fontSize: 12, height: 1.35),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: widget.controller.requestNotificationPermission,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFBBF24),
            ),
            child: const Text('Cấp quyền', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildIncomingRequestCard(CompanionAppState state, IncomingPairRequest req) {
    final remaining = req.secondsRemaining(DateTime.now().millisecondsSinceEpoch);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF172554),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3B82F6), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.laptop_windows_rounded, color: Color(0xFF60A5FA), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'YÊU CẦU KẾT NỐI ĐẾN',
                      style: TextStyle(
                        color: Color(0xFF93C5FD),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      req.windowsDeviceName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A8A),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${remaining}s',
                  style: const TextStyle(
                    color: Color(0xFFBFDBFE),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Máy tính tại địa chỉ ${req.remoteIp} muốn xem màn hình điện thoại này qua mạng LAN. Không có nội dung nào được truyền trước khi bạn đồng ý.',
            style: const TextStyle(color: Color(0xFFDBEAFE), fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.isResponding ? null : widget.controller.rejectIncomingRequest,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Từ chối'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFCA5A5),
                    side: const BorderSide(color: Color(0xFFEF4444)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: state.isResponding ? null : widget.controller.acceptIncomingRequest,
                  icon: state.isResponding
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.screen_share_rounded, size: 18),
                  label: const Text('Chấp nhận & Chia sẻ'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSessionCard(CompanionAppState state) {
    final isReconnecting = state.isReconnecting;
    final borderColor = isReconnecting ? const Color(0xFFF59E0B) : const Color(0xFF10B981);
    final bgColor = isReconnecting ? const Color(0xFF451A03) : const Color(0xFF064E3B);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                isReconnecting ? Icons.sync_problem_rounded : Icons.cast_connected_rounded,
                color: borderColor,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isReconnecting
                          ? 'ĐANG CHỜ KẾT NỐI LẠI (${state.reconnectSecondsLeft}s)'
                          : 'ĐANG CHIA SẺ MÀN HÌNH',
                      style: TextStyle(
                        color: borderColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      state.connectedWindowsName ?? 'Windows PC',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (state.streamWidth > 0 && state.streamHeight > 0)
                Text(
                  '${state.streamWidth}×${state.streamHeight}',
                  style: const TextStyle(
                    color: Color(0xFFA7F3D0),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            isReconnecting
                ? 'Kết nối tới Windows bị gián đoạn. Dịch vụ sẽ tự động dừng nếu không kết nối lại được.'
                : 'Foreground Service đang hoạt động. Bạn có thể chuyển sang ứng dụng khác hoặc đóng giao diện mà quá trình chia sẻ vẫn tiếp tục.',
            style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: widget.controller.stopMirroring,
            icon: const Icon(Icons.stop_circle_outlined, size: 18),
            label: const Text('Dừng chia sẻ màn hình'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFCA5A5),
              side: const BorderSide(color: Color(0xFFEF4444)),
              backgroundColor: const Color(0xFF450A0A).withValues(alpha: 0.45),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceIdentityCard(CompanionAppState state) {
    final ipsText = state.localIps.isEmpty ? 'Chưa có IP Wi-Fi LAN' : state.localIps.join(', ');
    final shortId = state.deviceId.length > 14
        ? '${state.deviceId.substring(0, 14)}...'
        : (state.deviceId.isEmpty ? 'Đang khởi tạo' : state.deviceId);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'THIẾT BỊ NÀY',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          _infoRow(Icons.smartphone_rounded, 'Tên thiết bị', state.deviceName),
          const SizedBox(height: 6),
          _infoRow(Icons.fingerprint_rounded, 'Mã định danh', shortId),
          const SizedBox(height: 6),
          _infoRow(Icons.wifi_rounded, 'Địa chỉ LAN', ipsText),
          const SizedBox(height: 6),
          _infoRow(
            Icons.settings_ethernet_rounded,
            'Cổng điều khiển',
            state.controlPort > 0 ? '${state.controlPort} (WebSocket)' : 'Đang mở...',
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 15, color: const Color(0xFF64748B)),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildDiscoveredHostsCard(CompanionAppState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'MÁY TÍNH WINDOWS TRONG MẠNG LAN',
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
                onTap: widget.controller.refreshDiscovery,
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh_rounded, size: 15, color: Color(0xFF38BDF8)),
                      SizedBox(width: 4),
                      Text(
                        'Làm mới',
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
          if (state.discoveredHosts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Đang tìm ứng dụng Mirroring trên Windows cùng mạng Wi-Fi...',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            )
          else
            ...state.discoveredHosts.map(
              (host) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.desktop_windows_rounded, color: Color(0xFF60A5FA), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            host.deviceName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            host.ipAddress,
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF065F46).withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        host.availability == 'streaming' ? 'Đang kết nối' : 'Trực tuyến',
                        style: const TextStyle(
                          color: Color(0xFF34D399),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFF38BDF8), size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsCard(List<String> logs) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'NHẬT KÝ HOẠT ĐỘNG',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          ...logs.take(5).map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    line,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        const Text(
          'Mở Mirroring trên Windows cùng mạng Wi-Fi, chọn điện thoại này và xác nhận để bắt đầu chia sẻ (không cần ADB hay Wireless Debugging).',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF64748B), fontSize: 11.5, height: 1.4),
        ),
        if (_appVersion != null) ...[
          const SizedBox(height: 8),
          Text(
            'Mirroring Companion v$_appVersion',
            style: const TextStyle(color: Color(0xFF475569), fontSize: 11),
          ),
        ],
      ],
    );
  }
}

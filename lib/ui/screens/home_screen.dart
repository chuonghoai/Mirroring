import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/models/connection_state.dart';
import '../../core/services/shortcut_service.dart';
import '../controllers/mirroring_controller.dart';

class HomeScreen extends StatefulWidget {
  final MirroringController controller;

  const HomeScreen({super.key, required this.controller});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final TextEditingController _ipController;
  late final TextEditingController _portController;
  String? _appVersion;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController();
    _portController = TextEditingController();
    _loadVersionFromPubspec();
  }

  Future<void> _loadVersionFromPubspec() async {
    try {
      String? versionStr;
      try {
        final content = await rootBundle.loadString('pubspec.yaml');
        final match = RegExp(r'^version:\s*([^\s+]+)', multiLine: true).firstMatch(content);
        if (match != null) {
          versionStr = match.group(1);
        }
      } catch (_) {}

      if (versionStr == null) {
        final file = File('pubspec.yaml');
        if (await file.exists()) {
          final content = await file.readAsString();
          final match = RegExp(r'^version:\s*([^\s+]+)', multiLine: true).firstMatch(content);
          if (match != null) {
            versionStr = match.group(1);
          }
        }
      }

      if (versionStr != null && mounted) {
        setState(() {
          _appVersion = versionStr;
        });
      }
    } catch (_) {}
  }

  Future<void> _confirmCreateShortcut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFF334155)),
        ),
        title: const Row(
          children: [
            Icon(Icons.desktop_windows_rounded, color: Color(0xFF38BDF8), size: 22),
            SizedBox(width: 10),
            Text(
              'Tạo shortcut Desktop',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        content: const Text(
          'Bạn có muốn tạo shortcut truy cập nhanh vào Desktop không?',
          style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Không', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Có, tạo ngay'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final success = await ShortcutService.createDesktopShortcut();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: success ? const Color(0xFF065F46) : const Color(0xFF7F1D1D),
            content: Text(
              success
                  ? 'Đã tạo shortcut "Mirroring" trên Desktop thành công!'
                  : 'Không thể tạo shortcut. Vui lòng thử lại.',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _handleConnect() {
    final state = widget.controller.state;
    final isBusy = state.isConnecting || state.isDisconnecting;
    if (!state.isConnected && !isBusy) {
      widget.controller.connect(
        _ipController.text,
        _portController.text.trim().isEmpty ? '5555' : _portController.text,
      );
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        final toolInfo = widget.controller.toolInfo;

        return Scaffold(
          backgroundColor: const Color(0xFF0F172A), // Slate 900
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header & Tool Status
                      _buildHeader(context, toolInfo, state.isCheckingTools),
                      const SizedBox(height: 18),

                      // Missing Tool Warning (if any)
                      if (!state.isCheckingTools && !toolInfo.isReady) ...[
                        _buildToolWarning(toolInfo),
                        const SizedBox(height: 14),
                      ],

                      // Connection Card
                      _buildConnectionCard(state),
                      const SizedBox(height: 16),

                      // Screen Control Card
                      _buildControlCard(state),

                      // Error Banner (if any)
                      if (state.errorMessage != null) ...[
                        const SizedBox(height: 14),
                        _buildErrorBanner(state.errorMessage!),
                      ],

                      const SizedBox(height: 18),
                      _buildHelpHint(),

                      const SizedBox(height: 14),
                      // App version & Desktop shortcut action
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (_appVersion != null) ...[
                            Text(
                              'phiên bản $_appVersion',
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 11,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const Text('•', style: TextStyle(color: Color(0xFF475569), fontSize: 11)),
                          ],
                          InkWell(
                            onTap: () => _confirmCreateShortcut(context),
                            borderRadius: BorderRadius.circular(4),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.desktop_windows_rounded, size: 12, color: Color(0xFF38BDF8)),
                                  SizedBox(width: 4),
                                  Text(
                                    'Tạo shortcut Desktop',
                                    style: TextStyle(
                                      color: Color(0xFF38BDF8),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, dynamic toolInfo, bool isChecking) {
    final bool isReady = !isChecking && toolInfo.isReady;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: [
              // App Logo from assets/app_icon.jpg (transparent PNG)
              Image.asset(
                'assets/app_icon.jpg',
                width: 38,
                height: 38,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
                  ),
                  child: const Icon(
                    Icons.stay_current_portrait_rounded,
                    color: Color(0xFF60A5FA),
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Android Mirroring',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'ADB + scrcpy Desktop',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),

        // Shortcut button in header
        Tooltip(
          message: 'Tạo shortcut ra màn hình Desktop',
          child: InkWell(
            onTap: () => _confirmCreateShortcut(context),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: const Color(0xFF334155).withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF475569).withValues(alpha: 0.5)),
              ),
              child: const Icon(
                Icons.desktop_windows_rounded,
                color: Color(0xFF94A3B8),
                size: 14,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),

        // Tool readiness badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: isChecking
                ? const Color(0xFF334155)
                : (isReady
                    ? const Color(0xFF065F46).withValues(alpha: 0.6)
                    : const Color(0xFF7F1D1D).withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isChecking
                  ? const Color(0xFF475569)
                  : (isReady
                      ? const Color(0xFF10B981).withValues(alpha: 0.4)
                      : const Color(0xFFEF4444).withValues(alpha: 0.4)),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isChecking
                      ? const Color(0xFF94A3B8)
                      : (isReady ? const Color(0xFF34D399) : const Color(0xFFF87171)),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                isChecking
                    ? 'Kiểm tra...'
                    : (isReady ? 'Sẵn sàng' : 'Thiếu công cụ'),
                style: TextStyle(
                  color: isChecking
                      ? const Color(0xFFCBD5E1)
                      : (isReady ? const Color(0xFF6EE7B7) : const Color(0xFFFCA5A5)),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToolWarning(dynamic toolInfo) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF450A0A).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFF87171), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              toolInfo.error ?? 'Thiếu công cụ ADB hoặc scrcpy.',
              style: const TextStyle(
                color: Color(0xFFFECACA),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionCard(MirroringAppState state) {
    final isConnected = state.isConnected;
    final isBusy = state.isConnecting || state.isDisconnecting;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B), // Slate 800
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'KẾT NỐI THIẾT BỊ',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              // Connection badge + Device name underneath
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildConnectionBadge(state),
                  if (isConnected && (state.deviceModel != null || state.connectedAddress != null)) ...[
                    const SizedBox(height: 5),
                    Text(
                      state.deviceModel ?? state.connectedAddress!,
                      style: const TextStyle(
                        color: Color(0xFF34D399),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Inputs Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // IP Address Input
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _ipController,
                  enabled: !isConnected && !isBusy,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _handleConnect(),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Địa chỉ IP',
                    labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    hintText: '192.168.1.10',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 13),
                    prefixIcon: const Icon(Icons.wifi_rounded, color: Color(0xFF64748B), size: 18),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF334155)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF1E293B)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Port Input
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _portController,
                  enabled: !isConnected && !isBusy,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _handleConnect(),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Port',
                    labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    hintText: '5555',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(Icons.numbers_rounded, color: Color(0xFF64748B), size: 18),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF334155)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF1E293B)),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Connect / Disconnect Buttons
          if (!isConnected)
            ElevatedButton.icon(
              onPressed: isBusy ? null : _handleConnect,
              icon: isBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.link_rounded, size: 18),
              label: Text(
                state.isConnecting ? 'Đang kết nối...' : 'Kết nối ADB',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB), // Blue 600
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: isBusy ? null : () => widget.controller.disconnect(),
              icon: isBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFEF4444)),
                    )
                  : const Icon(Icons.link_off_rounded, size: 18),
              label: Text(
                state.isDisconnecting ? 'Đang ngắt kết nối...' : 'Ngắt kết nối',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFF87171),
                side: const BorderSide(color: Color(0xFFDC2626)),
                backgroundColor: const Color(0xFF450A0A).withValues(alpha: 0.3),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControlCard(MirroringAppState state) {
    final isConnected = state.isConnected;
    final isRunning = state.scrcpyStatus == ScrcpyStatus.running;
    final isStarting = state.scrcpyStatus == ScrcpyStatus.starting;
    final isReopen = state.scrcpyStatus == ScrcpyStatus.reopenNeeded;

    return Container(
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
              const Text(
                'ĐIỀU KHIỂN MÀN HÌNH',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              if (isConnected && state.connectedAddress != null)
                Text(
                  state.deviceModel != null
                      ? '${state.deviceModel} (${state.connectedAddress})'
                      : state.connectedAddress!,
                  style: const TextStyle(
                    color: Color(0xFF60A5FA),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Open / Reopen Scrcpy Button
          ElevatedButton.icon(
            onPressed: (!isConnected || isRunning || isStarting)
                ? null
                : () => widget.controller.openScrcpy(),
            icon: isStarting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Icon(
                    isRunning
                        ? Icons.check_circle_rounded
                        : (isReopen ? Icons.replay_rounded : Icons.open_in_new_rounded),
                    size: 18,
                  ),
            label: Text(
              isRunning
                  ? 'Màn hình đang hiển thị'
                  : (isStarting
                      ? 'Đang khởi chạy...'
                      : (isReopen ? 'Mở lại Màn hình' : 'Mở Màn hình')),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: isRunning
                  ? const Color(0xFF059669) // Emerald 600
                  : const Color(0xFF0D9488), // Teal 600
              disabledBackgroundColor: const Color(0xFF334155),
              disabledForegroundColor: const Color(0xFF64748B),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
          ),

          if (!isConnected) ...[
            const SizedBox(height: 8),
            const Text(
              'Cần kết nối thiết bị qua ADB trước khi mở màn hình.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 11.5,
              ),
            ),
          ] else if (isRunning) ...[
            const SizedBox(height: 8),
            const Text(
              'Đang điều khiển qua chuột, bàn phím và đồng bộ clipboard.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF34D399),
                fontSize: 11.5,
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            const Text(
              'Đã sẵn sàng để mở màn hình thiết bị',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF38BDF8),
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConnectionBadge(MirroringAppState state) {
    Color bg;
    Color border;
    Color dot;
    String text;

    switch (state.connectionStatus) {
      case ConnectionStatus.connected:
        bg = const Color(0xFF065F46).withValues(alpha: 0.5);
        border = const Color(0xFF10B981).withValues(alpha: 0.4);
        dot = const Color(0xFF34D399);
        text = 'Đã kết nối';
        break;
      case ConnectionStatus.connecting:
        bg = const Color(0xFF78350F).withValues(alpha: 0.5);
        border = const Color(0xFFF59E0B).withValues(alpha: 0.4);
        dot = const Color(0xFFFBBF24);
        text = 'Đang kết nối';
        break;
      case ConnectionStatus.disconnecting:
        bg = const Color(0xFF78350F).withValues(alpha: 0.5);
        border = const Color(0xFFF59E0B).withValues(alpha: 0.4);
        dot = const Color(0xFFFBBF24);
        text = 'Đang ngắt...';
        break;
      case ConnectionStatus.error:
        bg = const Color(0xFF7F1D1D).withValues(alpha: 0.5);
        border = const Color(0xFFEF4444).withValues(alpha: 0.4);
        dot = const Color(0xFFF87171);
        text = 'Lỗi';
        break;
      case ConnectionStatus.disconnected:
        bg = const Color(0xFF334155).withValues(alpha: 0.6);
        border = const Color(0xFF475569).withValues(alpha: 0.4);
        dot = const Color(0xFF94A3B8);
        text = 'Chưa kết nối';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(color: dot, fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF450A0A).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFF87171), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFFECACA),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpHint() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF334155).withValues(alpha: 0.6)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFF64748B), size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Hướng dẫn: Bật "Wireless Debugging" (Gỡ lỗi qua Wi-Fi) trong Cài đặt cho nhà phát triển trên điện thoại Android để lấy địa chỉ IP và Port.',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

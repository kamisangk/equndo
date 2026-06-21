import 'package:flutter/material.dart';

import '../l10n/s.dart';
import '../services/credential_store_service.dart';
import '../services/discuz/equn_discuz_auth.dart';
import '../services/toast_service.dart';
import '../utils/blur_config.dart';
import '../widgets/auth/login_form.dart';
import '../widgets/common/ambient_background.dart';
import '../widgets/common/floating_logo.dart';
import '../widgets/common/loading_spinner.dart';
import 'webview_login_page.dart';

/// Equn Discuz 登录页。
///
/// 用户在本页输入账号密码后，WebView 会加载 Equn 原生 Discuz 登录页并自动提交
/// 表单。Discuz 站点若要求安全验证码，会继续在 WebView 内显示原生验证码，
/// 用户输入验证码后完成登录。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with TickerProviderStateMixin {
  String? _savedUsername;
  String? _savedPassword;
  bool _credentialsLoaded = false;

  late final AnimationController _entryController;
  final List<Animation<double>> _fade = [];
  final List<Animation<Offset>> _slide = [];

  @override
  void initState() {
    super.initState();
    _setupEntryAnimations();
    _loadSavedCredentials();
  }

  /// staggered 入场动画 (对齐 onboarding 的节奏)
  void _setupEntryAnimations() {
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    for (var i = 0; i < 5; i++) {
      final start = i * 0.12;
      final end = (start + 0.6).clamp(0.0, 1.0);
      _fade.add(
        Tween<double>(begin: 0, end: 1).animate(
          CurvedAnimation(
            parent: _entryController,
            curve: Interval(start, end, curve: Curves.easeOut),
          ),
        ),
      );
      _slide.add(
        Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entryController,
            curve: Interval(start, end, curve: Curves.easeOutCubic),
          ),
        ),
      );
    }
    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final saved = await CredentialStoreService().load();
      if (!mounted) return;
      setState(() {
        _savedUsername = saved.username;
        _savedPassword = saved.password;
        _credentialsLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _credentialsLoaded = true);
    }
  }

  /// 表单提交回调。返 true 表示走完成功路径并已 pop, false 留在表单。
  Future<bool> _handleSubmit({
    required String identifier,
    required String password,
    required bool rememberCredentials,
  }) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WebViewLoginPage(
          initialUrl: EqunDiscuzAuth.loginUrl,
          autoLoginUsername: identifier,
          autoLoginPassword: password,
          autoLoginRemember: rememberCredentials,
        ),
      ),
    );
    if (!mounted) return false;

    if (result == true) {
      if (rememberCredentials) {
        try {
          await CredentialStoreService().save(identifier, password);
        } catch (e) {
          debugPrint('[LoginPage] 保存账号失败,不影响登录: $e');
        }
      }
      if (!mounted) return true;
      ToastService.showSuccess(S.current.webviewLogin_loginSuccess);
      Navigator.of(context).pop(true);
      return true;
    }

    return false;
  }

  Future<void> _loginWithWebView([String? initialUrl]) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WebViewLoginPage(initialUrl: initialUrl),
      ),
    );
    if (result == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _clearSavedCredentials() async {
    await CredentialStoreService().clear();
    if (!mounted) return;
    setState(() {
      _savedUsername = null;
      _savedPassword = null;
    });
    ToastService.showSuccess('已清除保存的账号密码');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          const AmbientBackground(),
          SafeArea(
            child: Stack(
              children: [
                // 左上返回
                Positioned(
                  top: 4,
                  left: 4,
                  child: _entry(
                    0,
                    AmbientIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: '返回',
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ),
                // 右上清除保存的账号
                if (_credentialsLoaded && _savedUsername != null)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: _entry(
                      0,
                      AmbientIconButton(
                        icon: Icons.delete_outline_rounded,
                        tooltip: '清除保存的账号',
                        onPressed: _clearSavedCredentials,
                      ),
                    ),
                  ),
                // 主内容
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 32,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _entry(
                            0,
                            const Center(
                              child: FloatingLogo(size: 88, glowSize: 80),
                            ),
                          ),
                          const SizedBox(height: 28),
                          _entry(
                            1,
                            Text(
                              'EQUN 论坛',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _entry(
                            2,
                            Text(
                              context.l10n.login_slogan,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: scheme.onSurfaceVariant.withValues(
                                  alpha: 0.85,
                                ),
                                letterSpacing: 2,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          _entry(3, _buildFormCard(theme, scheme)),
                          const SizedBox(height: 24),
                          _entry(4, _buildAltLogin(context, scheme)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// staggered 入场包装 (index 对应 _fade/_slide)
  Widget _entry(int i, Widget child) {
    return FadeTransition(
      opacity: _fade[i],
      child: SlideTransition(position: _slide[i], child: child),
    );
  }

  /// 磨砂玻璃表单卡片
  Widget _buildFormCard(ThemeData theme, ColorScheme scheme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.4 : 0.1,
            ),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: createBlurFilter(blurSigma),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: !_credentialsLoaded
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: LoadingSpinner(size: 40)),
                  )
                : LoginForm(
                    onSubmit: _handleSubmit,
                    onForgotPassword: () =>
                        _loginWithWebView(EqunDiscuzAuth.lostPasswordUrl),
                    savedUsername: _savedUsername,
                    savedPassword: _savedPassword,
                  ),
          ),
        ),
      ),
    );
  }

  /// 分割线 + 网页登录 / 注册
  Widget _buildAltLogin(BuildContext context, ColorScheme scheme) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _DividerWithLabel(label: '或'),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => _loginWithWebView(),
          icon: const Icon(Icons.open_in_browser, size: 20),
          label: const Text('网页登录 / 注册'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          context.l10n.login_browserHint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}

class _DividerWithLabel extends StatelessWidget {
  const _DividerWithLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}

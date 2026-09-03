import 'package:flutter/material.dart';

import '../core/auth/session_controller.dart';
import '../core/config/app_config.dart';
import '../core/networking/api_client.dart';
import '../core/theme/platform_theme.dart';
import '../features/auth/presentation/access_denied_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/shell/presentation/platform_shell.dart';

class ChangishaPlatformApp extends StatefulWidget {
  const ChangishaPlatformApp({super.key});

  @override
  State<ChangishaPlatformApp> createState() => _ChangishaPlatformAppState();
}

class _ChangishaPlatformAppState extends State<ChangishaPlatformApp> {
  late final SessionController _controller;

  @override
  void initState() {
    super.initState();
    final config = AppConfig.fromEnvironment();
    final api = ApiClient(
      config: config,
      accessTokenProvider: () => _controller.accessToken,
    );
    _controller = SessionController(api: api);
    _controller.bootstrap();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Changisha Platform',
      debugShowCheckedModeBanner: false,
      theme: platformTheme(),
      home: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          switch (_controller.bootstrapState) {
            case BootstrapState.loading:
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            case BootstrapState.loggedOut:
              return LoginScreen(controller: _controller);
            case BootstrapState.accessDenied:
              return AccessDeniedScreen(controller: _controller);
            case BootstrapState.ready:
              return PlatformShell(controller: _controller);
          }
        },
      ),
    );
  }
}

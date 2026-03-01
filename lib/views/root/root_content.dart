part of 'root_view.dart';

class _RootContent extends StatelessWidget {
  const _RootContent(
    this.viewModel,
    this.rootProvider,
  );

  final RootViewModel viewModel;
  final RootProvider rootProvider;

  @override
  Widget build(BuildContext context) {
    final globalPrefs = context.watch<DevicePreferencesProvider>().preferences;
    final List<IconButtonSideItem> sideItems = SideItems.getSideMenuItems();

    return SpStoryPreferenceTheme(
      preferences: StoryPreferencesDbModel.create().copyWith(
        backgroundImagePath: globalPrefs.backgroundImagePath,
      ),
      child: SpAppLockWrapper(
        child: SpOnboardingWrapper(
          onOnboarded: () {
            NewBadgeStorage().remove();
          },
          child: PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) {
              if (!SpAppLockWrapper.authenticated(context)) return;
              if (!didPop) {
                final NavigatorState? navigator = rootProvider.navigatorKey.currentState;
                if (navigator?.canPop() ?? false) navigator?.maybePop(result);
              }
            },
            child: Scaffold(
              extendBody: true,
              extendBodyBehindAppBar: true,
              body: Stack(
                children: [
                  // GROK GLOBAL BACKGROUND HACK - forces your Calm/Erotic on EVERY screen
                  Positioned.fill(
                    child: Builder(
                      builder: (context) {
                        final String? path = globalPrefs.backgroundImagePath;
                        if (path == null || !path.startsWith('assets/')) {
                          return const SizedBox.shrink();
                        }
                        return Image.asset(
                          path,
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                        );
                      },
                    ),
                  ),
                  Builder(builder: (context) => buildPagesNavigator(context)),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: RootSideBar(rootProvider: rootProvider, sideItems: sideItems),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildPagesNavigator(BuildContext context) {
    double left;
    double right;

    bool bigScreen = WindowedDetectorService.isBigWindow(context);

    final screenPadding = MediaQuery.paddingOf(context);

    if (bigScreen) {
      left = 88;
      right = screenPadding.right + 88;
    } else {
      left = screenPadding.left;
      right = screenPadding.right;
    }

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        padding: EdgeInsets.only(
          top: screenPadding.top,
          left: left,
          bottom: screenPadding.bottom,
          right: right,
        ),
      ),
      child: HeroControllerScope(
        controller: rootProvider.heroController,
        child: Navigator(
          key: rootProvider.navigatorKey,
          initialRoute: rootProvider.initialRoute,
          onGenerateRoute: (settings) => rootProvider.generateRoute(settings),
          observers: [
            _RootRouteObserver(
              onPop: (route, previousRoute) {
                if (previousRoute?.settings.name == null) return;
                rootProvider.selectedRootRouteNameNotifier.value = previousRoute!.settings.name!;
                autoBackupWhenNavigateToHome(previousRoute, context);
              },
              onPush: (route, previousRoute) {
                if (route.settings.name == null) return;
                rootProvider.selectedRootRouteNameNotifier.value = route.settings.name!;
                autoBackupWhenNavigateToHome(route, context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void autoBackupWhenNavigateToHome(Route<dynamic> route, BuildContext context) {
    if (route.settings.name == const HomeRoute().routeName && context.read<InAppPurchaseProvider>().autoBackups) {
      final backupProvider = context.read<BackupProvider>();
      if (backupProvider.readyToSynced && !backupProvider.allYearSynced) {
        backupProvider.recheckAndSync();
      }
    }
  }
}
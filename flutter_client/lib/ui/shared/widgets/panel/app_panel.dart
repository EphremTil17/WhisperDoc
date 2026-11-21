import 'package:flutter/services.dart';
import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';
import 'package:flutter_client/ui/shared/widgets/custom_title_bar.dart';
import 'package:material_ui/material_ui.dart';

/// A full-window page over the home screen: the title bar, a back button
/// with the panel's title, then a list of [children] (or a custom [body]),
/// and an optional [footer] above a 1px rule.
///
/// Open one with [AppPanel.push]; the back button pops it.
class AppPanel extends StatelessWidget {
  const AppPanel({
    super.key,
    required this.title,
    this.children = const [],
    this.body,
    this.actions = const [],
    this.footer,
    this.autofocus = true,
  });

  /// Lists sit on an 8px inset so row hover fills reach past their rules.
  static const double listInset = AppSpace.sm;

  final String title;

  /// Panel content as a scrolling list, usually [PanelSection]s.
  final List<Widget> children;

  /// Replaces [children] when the panel draws its own content (logs).
  final Widget? body;

  /// Icon buttons at the end of the header.
  final List<Widget> actions;

  final Widget? footer;

  /// Takes focus on open so Esc works at once. Off when a field inside
  /// autofocuses instead (the first autofocus request in a scope wins).
  final bool autofocus;

  /// Opens [panel] over the current route with a short fade.
  static Future<T?> push<T>(BuildContext context, Widget panel) =>
      Navigator.of(context).push<T>(
        PageRouteBuilder<T>(
          transitionDuration: AppMotion.quick,
          reverseTransitionDuration: AppMotion.quick,
          pageBuilder: (_, _, _) => panel,
          transitionsBuilder: (_, animation, _, child) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: AppMotion.ease),
            child: child,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final bottom = footer;

    // Esc goes back, as it closed the dialogs these panels replaced.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: autofocus,
        child: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const CustomTitleBar(),
              SizedBox(
                height: AppSizes.header,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: AppSpace.sm,
                    end: AppSpace.xs,
                  ),
                  child: Row(
                    spacing: AppSpace.xs,
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(
                          AppIcons.chevronLeft,
                          color: AppColors.text,
                        ),
                      ),
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: CrispText(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.title.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      ...actions,
                    ],
                  ),
                ),
              ),
              Expanded(
                child:
                    body ??
                    ListView(
                      padding: const EdgeInsets.only(
                        left: listInset,
                        right: listInset,
                        bottom: AppSpace.lg,
                      ),
                      children: children,
                    ),
              ),
              if (bottom != null)
                DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.rule)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.lg,
                      vertical: AppSpace.sm,
                    ),
                    child: bottom,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

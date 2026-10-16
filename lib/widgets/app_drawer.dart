import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../screens/browser_screen.dart';
import '../screens/community_screen.dart';
import '../services/community_service.dart';
import '../screens/downloads_screen.dart';
import '../screens/library_screen.dart';
import '../screens/plans_screen.dart';
import '../screens/remove_ads_screen.dart';
import '../services/auth_service.dart';
import '../services/notice_service.dart';
import '../services/app_sharer.dart';
import '../services/app_updater.dart';
import '../services/subscription_service.dart';
import '../services/settings_service.dart';
import '../utils/l10n.dart';
import 'language_sheet.dart';
import 'theme_sheet.dart';
import '../theme/app_theme.dart';

void _toast(BuildContext c, String msg) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(msg)));

/// Side menu: Premium / Remove ads, Downloads, Library, Themes, Language,
/// Floating Player, Video Quality, Notice, Join Us, Copyright, Share App,
/// Update App, Exit.
class DamiMoviesDrawer extends StatelessWidget {
  const DamiMoviesDrawer({super.key});

  void _go(BuildContext context, Future<void> Function(BuildContext) action) {
    final nav = Navigator.of(context);
    nav.pop(); // close drawer
    action(nav.context);
  }

  Future<void> _push(BuildContext c, Widget w) =>
      Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => w));

  Future<void> _openLink(BuildContext c, String url, String label) async {
    if (url.isEmpty) {
      _toast(c, '{label} link is not set up yet'.trArgs({'label': label}));
      return;
    }
    if (!await openExternally(url) && c.mounted) {
      _toast(c, 'Could not open the link'.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String label, Future<void> Function(BuildContext) f) =>
        ListTile(
          dense: true,
          leading: Icon(icon, size: 21),
          title: Text(label,
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          onTap: () => _go(context, f),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18),
          minVerticalPadding: 6,
          horizontalTitleGap: 12,
        );

    // "Subscription: Active" + the end date and days left.
    Widget subscriptionItem() {
      final sub = SubscriptionService.instance;
      final date = sub.expiresLabel;
      final left = sub.daysLeft;
      final detail = [
        if (date != null) 'No ads until {date}'.trArgs({'date': date}),
        if (left != null && left <= 400)
          (left == 1 ? '{n} day left' : '{n} days left').trArgs({'n': left}),
      ].join(' · ');
      return ListTile(
        dense: true,
        leading: Icon(Icons.verified_rounded, size: 21, color: Ui.green),
        title: Text('Subscription: Active'.tr,
            style: const TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w700)),
        subtitle: detail.isEmpty
            ? null
            : Text(detail, style: TextStyle(color: Ui.muted, fontSize: 11.5)),
        onTap: () => _go(context, (c) => _push(c, const RemoveAdsScreen())),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18),
        minVerticalPadding: 6,
        horizontalTitleGap: 12,
      );
    }

    return Drawer(
      backgroundColor: Ui.cardDeep,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
                20, MediaQuery.of(context).padding.top + 24, 20, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Ui.red.withValues(alpha: .28), Ui.cardDeep],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // App logo (the splash image) in place of the football icon
                // and the app name.
                Image.asset(
                  'assets/splash/splash.png',
                  height: 132,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 4),
                Text('${'Version'.tr}: ${AppConfig.appVersion}',
                    style: TextStyle(color: Ui.muted, fontSize: 11.5)),
                if (AuthService.instance.user != null) ...[
                  const SizedBox(height: 14),
                  _AccountRow(user: AuthService.instance.user!),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView(
              // Bottom padding keeps 'Exit' clear of the phone navigation bar.
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewPadding.bottom + 16),
              children: [
                if (SubscriptionService.instance.visible)
                  item(
                      Icons.workspace_premium_rounded,
                      SubscriptionService.instance.isPremium
                          ? 'Premium (active)'.tr
                          : 'Go Premium - no ads'.tr,
                      (c) => _push(c, const PlansScreen())),
                // Token users: before = "Remove ads"; once ads are gone this
                // becomes the subscription status. (Paystack Premium has its
                // own item above, so it is not repeated.)
                if (SubscriptionService.instance.tokensVisible &&
                    !(SubscriptionService.instance.visible &&
                        SubscriptionService.instance.isPremium))
                  if (SubscriptionService.instance.isPremium)
                    subscriptionItem()
                  else
                    item(Icons.block_rounded, 'Remove ads'.tr,
                        (c) => _push(c, const RemoveAdsScreen())),
                item(Icons.download_rounded, 'Downloads'.tr,
                    (c) => _push(c, const DownloadsScreen())),
                item(Icons.forum_rounded, 'Movie Community',
                    (c) => _push(c, const CommunityScreen(standalone: true))),
                item(Icons.bookmark_rounded, 'My Library'.tr,
                    (c) => _push(c, const LibraryScreen())),
                item(Icons.palette_rounded, 'Themes'.tr, showThemeSheet),
                item(Icons.language_rounded, 'Language'.tr, showLanguageSheet),
                item(Icons.picture_in_picture_alt_rounded, 'Floating Player'.tr,
                    showFloatingPlayerDialog),
                item(Icons.settings_rounded, 'Video Quality Setting'.tr,
                    showLowQualityDialog),
                item(Icons.campaign_rounded, 'Notice'.tr, showNoticeDialog),
                item(Icons.chat_rounded, 'Join Us'.tr,
                    (c) => _openLink(c, AppConfig.joinUrl, 'Join Us'.tr)),
                item(Icons.copyright_rounded, 'Copyright'.tr,
                    showCopyrightDialog),
                item(Icons.share_rounded, 'Share App'.tr,
                    (c) => AppSharer.instance.share(c)),
                item(Icons.sync_rounded, 'Update App'.tr,
                    (c) => AppUpdater.instance.update(c)),
                if (AppConfig.loginRequired &&
                    AuthService.instance.user != null)
                  item(Icons.logout_rounded, 'Sign out'.tr, confirmSignOut),
                item(Icons.exit_to_app_rounded, 'Exit'.tr,
                    (c) async => SystemNavigator.pop()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Gmail avatar, name and address at the top of the menu.
class _AccountRow extends StatelessWidget {
  final AuthUser user;
  const _AccountRow({required this.user});

  @override
  Widget build(BuildContext context) {
    final initial =
        user.name.trim().isEmpty ? '?' : user.name.trim()[0].toUpperCase();
    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: Ui.red,
          foregroundImage:
              user.photoUrl == null ? null : NetworkImage(user.photoUrl!),
          child: Text(initial,
              style: TextStyle(
                  color: Ui.palette.onAccent, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800)),
              Text(user.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Ui.muted, fontSize: 11.5)),
            ],
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ dialogs

Future<void> confirmSignOut(BuildContext context) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Sign out'.tr),
      content: Text('You will need to log in with Gmail again.'.tr),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('CANCEL'.tr)),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('SIGN OUT'.tr)),
      ],
    ),
  );
  if (yes == true) {
    await AuthService.instance.signOut();
    CommunityService.instance.clear();
  }
}

Future<void> showLowQualityDialog(BuildContext context) async {
  var on = await Settings.forceLowQuality();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text('Force To Low Video Quality'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Enable this option to reduce buffering on slow connections. '
                        'This will reduce video quality but improve playback stability.'
                    .tr,
                style: const TextStyle(fontWeight: FontWeight.w700, height: 1.3)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text('Force to Low Quality'.tr,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                ),
                Switch(
                  value: on,
                  onChanged: (v) {
                    set(() => on = v);
                    Settings.setForceLowQuality(v);
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text('CLOSE'.tr)),
        ],
      ),
    ),
  );
}

Future<void> showFloatingPlayerDialog(BuildContext context) async {
  var on = await Settings.floatingPlayer();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text('Floating Player'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Adds a button to the player that shrinks the video into a '
                        'small floating window (picture-in-picture) so you can keep '
                        'watching while using other apps.'
                    .tr,
                style: const TextStyle(fontWeight: FontWeight.w700, height: 1.3)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text('Enable Floating Player'.tr,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                ),
                Switch(
                  value: on,
                  onChanged: (v) {
                    set(() => on = v);
                    Settings.setFloatingPlayer(v);
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text('CLOSE'.tr)),
        ],
      ),
    ),
  );
}

Future<void> showCopyrightDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Copyright Alert'.tr),
      content: Text(
          'DamiMovies does not host, upload or own any of the movies, '
                  'series or videos shown in this application. All content is the '
                  'copyright of its respective owners, and you are responsible for '
                  'making sure you have the right to watch what you play.'
              .tr,
          style: const TextStyle(fontWeight: FontWeight.w700, height: 1.3)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: Text('OK'.tr)),
      ],
    ),
  );
}

Future<void> showNoticeDialog(BuildContext context) =>
    NoticeService.instance.showFromMenu(context);

/// Home shell — bottom-nav container for the two primary journeys:
/// the mother's health dashboard and the child's tracking map. Rebuilds on
/// AppController changes via its `changes` stream.
library;


import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../app/app_controller.dart';
import '../core/geofence.dart';
import '../domain/appointment.dart' show nextAppointment;
import '../domain/child_tracker_state.dart' show currentZone;
import '../domain/geofence_alerts.dart';
import '../domain/notification_route.dart';
import '../domain/hydration.dart';
import '../domain/setup_checklist.dart';
import '../domain/weekly_digest.dart';
import '../l10n/l10n.dart';
import '../l10n/l10n_scope.dart';
import 'advisor/advisor_screen.dart';
import 'chat/assistant_chat_screen.dart';
import 'common/skeleton.dart';
import 'ds_widgets.dart';
import 'theme.dart';
import 'appointments/appointments_screen.dart';
import 'auth/sign_in_route.dart';
import 'calendar/antenatal_plan_screen.dart';
import 'calendar/kick_session_screen.dart';
import 'calendar/day_log_sheet.dart';
import 'calendar/pregnancy_weight_screen.dart';
import '../domain/weight.dart';
import '../domain/child_development.dart';
import '../domain/baby_development_content.dart' show childAgeDays;
import '../domain/family.dart';
import '../domain/cycle_predictions.dart';
import '../domain/cycle_insights.dart';
import 'calendar/womens_health_screen.dart';
import 'dashboard/health_dashboard_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../domain/timeline_content.dart';
import 'content/lesson_player_screen.dart';
import 'content/guides_screen.dart';
import 'dashboard/log_sleep_sheet.dart';
import 'dashboard/log_vitals_sheet.dart';
import 'dashboard/water_history_screen.dart';
import 'settings/reminders_center_screen.dart';
import 'settings/support_thread_route.dart';
import 'tracking/child_detail_screen.dart';
import 'profile/family_access_screen.dart';
import 'profile/my_order_screen.dart';
import 'shop/shop_screen.dart';
import '../domain/shop_catalogue.dart';
import 'profile/profile_screen.dart';
import 'tracking/alerts_screen.dart';
import 'tracking/notification_centre_screen.dart';
import '../domain/day_history.dart';
import '../domain/family_access.dart';
import '../domain/my_order.dart';
import 'tracking/child_map_screen.dart';
import 'tracking/child_tools_sheet.dart';
import 'tracking/tracking_map.dart';
import 'tracking/day_history_screen.dart';
import 'tracking/family_sheets.dart';
import 'tracking/zones_screen.dart';


class HomeShell extends StatefulWidget {
  final AppController controller;

  /// The content catalogue in use — authored asset or seeded fallback.
  final ContentCatalog catalog;

  /// The live catalogue, when there is one (the ContentStore notifier).
  ///
  /// [catalog] is a SNAPSHOT: the shell is rebuilt from it by app.dart, but a
  /// route pushed on top of the shell sits outside that builder and would keep
  /// whatever was current at the moment of the tap. The guides screen is a
  /// library somebody may leave open, so it listens instead — a stage
  /// published in the back office reaches it without a cold start. Null in
  /// tests and offline builds, which fall back to the snapshot.
  final ValueListenable<ContentCatalog>? catalogSource;
  const HomeShell({
    super.key,
    required this.controller,
    required this.catalog,
    this.catalogSource,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// Tab indices, so the deep-link handler names screens rather than counting.
  static const _tabDashboard = 0;
  static const _tabChild = 2;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    // Screen 38's other half: a notification was tapped while the app was
    // somewhere else. The tap arrives on a platform callback with no
    // BuildContext, so the controller holds the request and the shell — the
    // first thing under the Navigator — spends it. After the frame, because
    // pushing a route from inside build() is not allowed.
    if (c.pendingDestination != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final d = c.takePendingDestination();
        if (d != null) _goTo(d, c);
      });
    }
    final loc = c.childLocation;
    // How long the child has been in their current zone (from the alert feed).
    final curZone = loc == null ? null : currentZone(loc.coords, c.geofences);
    final zoneEnteredAt = curZone == null ? null : zoneEntryTime(c.alerts, c.childName, curZone);

    final l = L10nScope.of(context);
    // Which day's clip belongs to this family — computed once, spent on the
    // dashboard's «Аудио дня».
    final audio = _audioDay(c);

    final pages = [
      HealthDashboardView(
        samples: c.samples,
        sleepNights: c.sleepNights,
        greetingName: c.displayName,
        photoPath: c.profile.photoPath,
        currentLocale: c.locale,
        summaryStatus: _summaryStatus(c, l),
        statusChip: _statusChip(c, l),
        statusChipPregnancy: c.isPregnant,
        statusChipLate: _statusChipLate(c),
        bandNotMeasuring: c.isBandNotMeasuring,
        wearable: c.latestWearable,
        // How many days the last backfill from the watch actually brought back
        // — the span the charts below cover, stated rather than implied.
        watchHistoryDays: c.wearableHistory?.coveredDays,
        onOpenStatus: () => setState(() => _index = 1),
        weeklyDigest: computeWeeklyDigest(
          c.dayLogs, c.waterLog, c.sleepNights, DateTime.now(),
          waterGoal: c.waterGoal,
        ),
        setupProgress: computeSetupProgress(
          signedIn: c.isSignedIn,
          hasName: c.displayName.trim().isNotEmpty,
          hasHealthData: c.dueDate != null || c.periodDays.isNotEmpty,
          hasChild: c.children.isNotEmpty,
          hasZone: c.children.any((ch) => ch.geofences.isNotEmpty),
          hasDetails: c.profile.hasBirthDate && c.profile.hasCity,
          hasBackup: c.lastExportAt != null,
        ),
        // Each unfinished step lands on the screen that COMPLETES it, not a
        // catch-all Profile tab (tapping "add a child" used to open Profile).
        onOpenSetup: (step) {
          switch (step) {
            case SetupStep.signIn:
              openSignIn(context, c);
            case SetupStep.profileName:
            case SetupStep.details: // birth date + city live in the same editor
              showEditProfileSheet(context, c);
            case SetupStep.healthMode: // due date / first period → women's health
              setState(() => _index = 1);
            case SetupStep.child:
              showAddChildSheet(context, c);
            case SetupStep.zone: // safe zones are added on the child map
              setState(() => _index = 2);
            case SetupStep.backup: // export lives on the profile tab
              setState(() => _index = 3);
          }
        },
        onLogVitals: () => _logVitals(context, c),
        // Screen 05's dark card. The vitals sheet already owns the camera path;
        // this surfaces it on the screen of somebody with no band, where it is
        // the fastest way to get a blood pressure in. Null with no server, so
        // the card is not offered when it cannot work.
        onScanMonitor: c.api == null ? null : () => _logVitals(context, c),
        awaitingRepeat: c.awaitingRepeat,
        nextAppointment: nextAppointment(c.appointments, DateTime.now()),
        nowForAppointment: DateTime.now(),
        onOpenAppointments: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AppointmentsScreen(controller: c)),
        ),
        // The state antenatal protocol's due/next visit, shown beside her own
        // appointment. Only while pregnant (gestation known).
        pregnancyWeek: c.isPregnant ? c.gestation?.week : null,
        onOpenAntenatalPlan: c.gestation == null
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AntenatalPlanScreen(
                    week: c.gestation!.week,
                    dueDate: c.dueDate,
                    onBook: (visit, at) => c.addAppointment(
                      l.t('an_book_title', {'n': visit.number}), at),
                  ),
                )),
        onLocaleChange: c.setLocale,
        onOpenProfile: () => setState(() => _index = 3),
        // Screen 39, on the tab the app opens on.
        //
        // _openNotificationCentre had exactly two callers — the child map's
        // bell and the deep-link handler — so the notification centre lived
        // only on «Ребёнок». A woman who is pregnant and has added no child
        // never opens that tab, and the back office publishes рассылки to
        // exactly her: delivered, counted, unreachable. Same method, same
        // screen, same unread count as the map's bell.
        onOpenNotifications: () => _openNotificationCentre(context, c),
        notificationCount: c.unreadAlertCount,
        onOpenAdvisor: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AdvisorScreen(
            samples: c.samples,
            lastNight: c.lastNight,
            recentNights: c.sleepNights,
            waterCount: c.waterFor(DateTime.now()),
            waterGoal: c.waterGoal,
            nowHour: DateTime.now().hour,
            // The conversational assistant, when its controller is attached
            // (a network build). Null in offline/test builds hides the entry.
            onOpenChat: c.chat == null
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => AssistantChatScreen(controller: c.chat!)),
                    ),
          )),
        ),
        waterCount: c.waterFor(DateTime.now()),
        waterGoal: c.waterGoal,
        // «Аудио дня» (screens 04 and 55). Same track and same day the
        // calendar and the development screen use — one recording, keyed on
        // where this family is, not three different clips.
        audioTrack: audio?.track,
        audioDay: audio?.day,
        timelineStage: _stageFor(c),
        timelineItems: _contentFor(c),
        onOpenContent: _openContent,
        // Screen 27 — «Гиды». NOT gated on having a stage: that gate is the
        // reason a woman with no due date and no child could reach none of the
        // 364 published items, and it is the one case the library matters
        // most in. The stage screen is still reachable, from inside it.
        onSeeAllContent: () => _openGuides(context, c),
        // Screen 53's hero and its three quick actions. Passing the data AND
        // the handlers together: a hero wired to nothing is the defect this
        // screen already had once.
        gestation: c.gestation,
        // Screen 55: her cycle, and the three routers that let her tell the app
        // her stage changed — «Тест положительный» had no entry point at all.
        hasChild: c.children.isNotEmpty,
        // Screen 54's block. Only a child with a birth date has an age to
        // place her on the timeline, so one without falls through to the
        // cycle — the same rule the calendar follows.
        childHeroName: _heroChild(c)?.name,
        childHeroAgeMonths: _heroChild(c) == null
            ? null
            : ageInMonths(_heroChild(c)!.dateOfBirth!, DateTime.now()),
        childGrowth: _heroChild(c) == null ? const [] : c.growthFor(_heroChild(c)!.id),
        onOpenChild: () => setState(() => _index = 2),
        cycleInfo: c.cycle,
        cyclePhase: cyclePhaseFor(c.cycle),
        cycleConfidence: () {
          final reg = cycleRegularity(cycleHistory(c.periodDays));
          return predictionConfidence(
            completedCycles: reg.cyclesConsidered,
            variationDays: reg.variationDays,
          );
        }(),
        onPlanning: () => setState(() => _index = 1), // the cycle calendar
        onPregnant: () => _recordPositiveTest(context, c),
        onHasChild: () => showAddChildSheet(context, c),
        kicksToday: c.logFor(DateTime.now()).kicks,
        loggedWellbeingToday: c.logFor(DateTime.now()).mood != null,
        latestWeightKg: c.weights.isEmpty ? null : c.weights.last.kg,
        onLogKick: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => KickSessionScreen(
                  onSave: (n, elapsed) =>
                      c.logKickSession(DateTime.now(), n, elapsed)),
            )),
        onLogDay: () => showDayLogSheet(context, c, DateTime.now()),
        onLogWeight: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PregnancyWeightScreen(
                  weeklyRateKg: weeklyGainRate(c.weights)),
            )),
        onLogSleep: () => _logSleep(context, c),
        onAddWater: () => c.addWater(DateTime.now()),
        onRemoveWater: () => c.addWater(DateTime.now(), -1),
        onSetWaterGoal: c.setWaterGoal,
        onOpenWaterHistory: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => WaterHistoryScreen(
            week: lastNDays(c.waterLog, DateTime.now(), 7),
            goal: c.waterGoal,
            streak: waterStreak(c.waterLog, DateTime.now(), c.waterGoal),
            controller: c, // makes past days correctable
          ),
        )),
      ),
      WomensHealthScreen(
        controller: c,
        // The same published content the dashboard shows, filtered to the
        // viewer, so the pregnancy calendar carries this week's tips instead of
        // a bare header.
        tips: _contentFor(c),
        onOpenTip: _openContent,
        onSeeAllTips: () => setState(() => _index = 0), // the dashboard hosts the full shelf
      ),
      ChildMapScreen(
        childName: c.childName,
        hasNamedChild: c.hasNamedChild,
        childLocation: loc?.coords,
        updatedAt: loc?.at,
        fences: c.geofences,
        now: DateTime.now(),
        mapBuilder: _buildMap,
        childOptions: [for (final ch in c.children) (id: ch.id, name: ch.name)],
        selectedChildId: c.selectedChild?.id,
        childAgeMonths: c.selectedChild?.hasDateOfBirth == true
            ? c.selectedChild!.ageInMonths(DateTime.now())
            : null,
        hasPairedTracker: (c.selectedChild?.tagId ?? '').isNotEmpty,
        onSelectChild: c.selectChild,
        onAddChild: () => showAddChildSheet(context, c),
        onAddDevice: () => showAddDeviceSheet(context, c),
        onManageZones: c.selectedChild == null
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ZonesScreen(controller: c, childId: c.selectedChild!.id),
                )),
        // UNREAD, not total. The badge counted everything that had ever
        // happened, so it never went down and stopped meaning anything —
        // which is the state a badge is worst in, because it also stops
        // meaning anything on the day something is actually wrong.
        alertCount: c.unreadAlertCount,
        onOpenAlerts: () => _openNotificationCentre(context, c),
        batteryPct: c.selectedChildBattery,
        batteryHistory: c.selectedChildBatteryHistory,
        zoneEnteredAt: zoneEnteredAt,
        lastCheckInAt: lastCheckIn(c.alerts, c.childName),
        onCheckIn: c.selectedChild == null ? null : () => c.logChildEvent(AlertKind.checkIn),
        onSos: c.selectedChild == null ? null : () => c.logChildEvent(AlertKind.sos),
        // Screen 47. Needs a child AND a server — the trail lives only on the
        // server, so offline the button is absent rather than opening a screen
        // that can never load.
        onDayHistory: (c.selectedChild == null || c.api == null)
            ? null
            : () => _openDayHistory(context, c),
        // The child's card, from the tab it belongs to. It used to be reachable
        // only through Настройки → Дети, and everything under it — медкарта,
        // прививки, рост и вес, развитие, дневник новорождённого, детектор
        // плача, прикорм, безопасность дома, болезни — inherited that dead end.
        // The map already knows which child is selected, so no picker here.
        onOpenChildCard: c.selectedChild == null
            ? null
            : () => _openChildCard(context, c, childId: c.selectedChild!.id),
        // Screen 15a. The nine care screens, named, one tap from this tab —
        // they used to be three taps behind that folder glyph and mentioned
        // nowhere on the tab they belong to.
        onOpenTools: c.selectedChild == null
            ? null
            : () => showChildToolsSheet(context, c,
                childId: c.selectedChild!.id, now: DateTime.now()),
        // Screen 20. The strip at the top of the shell says the app is
        // offline; this is what the MAP does about it, which is the screen
        // where being wrong about staleness costs something.
        isOffline: c.isOffline,
        onRefresh: c.api == null ? null : () => c.refreshChildLocation(),
      ),
      ProfileScreen(
        controller: c,
        // «2 детей» opens a CHILD, not the map. It used to switch to the Бала
        // tab, which is a live map with no route to the child card at all, so
        // the tile that says how many children she has landed on a screen that
        // could not show her any of them. With more than one it asks which —
        // guessing there opens the wrong sibling's medical record.
        onOpenChildren: () => _openChildCard(context, c),
        // Trackers ARE managed on the map, so this one is unchanged.
        onOpenDevices: () => setState(() => _index = 2),
        // Screen 40. The grants live on the server; without one the row is
        // absent rather than opening a screen that can only fail.
        onOpenFamilyAccess:
            c.api == null ? null : () => _openFamilyAccess(context, c),
        // Screen 42. The orders live on the server, matched on her phone.
        onOpenMyOrder: c.api == null ? null : () => _openMyOrder(context, c),
        // Screen 41. Always available — the offer does not need a server, and
        // the WhatsApp number is fetched when the screen opens.
        onOpenShop: () => _openShop(context, c),
        // Screen 27, from the second place somebody looks for "everything the
        // app has". The Today card is the other; one entry point on a tab she
        // may never scroll to the bottom of is how a library goes unfound.
        onOpenGuides: () => _openGuides(context, c),
        // Screen 43. Профиль → «Поддержка», not Профиль → ⚙ → «Помощь» →
        // «Открыть переписку»: four taps to an answer somebody is waiting for,
        // with the unread badge computed on the third of them. Настройки keeps
        // its own «Помощь и поддержка» row — that is the help hub (FAQ,
        // WhatsApp, self-service); this is the conversation.
        onOpenSupport: c.api == null ? null : () => openSupportThread(context, c),
        loadSupportUnread:
            c.api == null ? null : () => unreadSupportAnswers(c),
      ),
    ];

    return Scaffold(
      body: Column(
        children: [
          // A quiet offline strip across the top of the app — so a stale reading
          // or a not-yet-synced entry reads as "waiting for the network", not as
          // broken. Driven by the connectivity service wired in main.dart.
          if (c.isOffline)
            Material(
              color: Palette.amber.withValues(alpha: 0.16),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.wifi_off_rounded, size: 15, color: Palette.amber),
                    const SizedBox(width: 8),
                    Text(l.t('offline_banner'),
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Palette.text)),
                  ]),
                ),
              ),
            ),
          Expanded(child: IndexedStack(index: _index, children: pages)),
        ],
      ),
      bottomNavigationBar: DsTabBarSurface(
        child: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.favorite_outline),
              selectedIcon: const Icon(Icons.favorite),
              label: l.t('nav_today')),
          NavigationDestination(
              icon: const Icon(Icons.calendar_today_outlined),
              selectedIcon: const Icon(Icons.calendar_month),
              label: l.t('nav_calendar')),
          NavigationDestination(
              icon: const Icon(Icons.location_on_outlined),
              selectedIcon: const Icon(Icons.location_on),
              label: l.t('nav_child')),
          NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: l.t('nav_profile')),
        ],
        ),
      ),
    );
  }

  /// A one-line pregnancy/cycle status for the shared health summary (empty when
  /// there's nothing to say).
  String _summaryStatus(AppController c, L10n l) {
    if (c.isPregnant) {
      final g = c.gestation;
      if (g != null) return l.t('share_status_pregnancy', {'week': g.week});
      return '';
    }
    final cyc = c.cycle;
    if (cyc.hasData && cyc.cycleDay != null) {
      final until = cyc.daysUntilNextPeriod ?? 0;
      return until >= 0
          ? l.t('share_status_cycle', {'day': cyc.cycleDay, 'n': until})
          : l.t('share_status_cycle_late', {'day': cyc.cycleDay, 'n': -until});
    }
    return '';
  }

/// Screen 27 — «Гиды».
  ///
  /// The library, not this week's shelf. Reachable with no due date and no
  /// child, which the weekly card never was.
  ///
  /// Wrapped in a ValueListenableBuilder on the catalogue where there is one:
  /// a pushed route sits outside the shell's own builder, so without this the
  /// screen would hold whatever was published at the instant of the tap, for
  /// as long as she keeps it open.
  void _openGuides(BuildContext context, AppController c) {
    final source = widget.catalogSource;
    Widget screen(ContentCatalog catalog) {
      // Read INSIDE the builder, never captured at the instant of the tap. The
      // «Добавьте адрес» prompt on screen 37 opens the profile sheet from this
      // shell, and a profile captured here once would leave the screen she
      // saved it from still saying it is missing.
      final p = c.profile;
      return GuidesScreen(
        catalog: catalog,
        stage: _stageFor(c),
        viewer: ContentViewer(city: p.city, ageYears: p.ageYears(DateTime.now())),
        pregnant: c.isPregnant,
        onOpen: _openContent,
        // Screen 37 hangs off the red-flag card on this screen, and it needs
        // the three profile facts an ambulance call turns on: where to send
        // one, the city as the fallback line, and her own doctor's number —
        // which the app has been syncing for a year with one screen able to
        // dial it.
        address: p.address,
        city: p.city,
        doctorPhone: p.doctorPhone,
        onEditProfile: () => showEditProfileSheet(context, c),
      );
    }

    Navigator.of(context).push(MaterialPageRoute(
      // Rebuilt on every controller change, like the notification centre: a
      // pushed route sits outside the shell's own StreamBuilder, so without
      // this the screen — and screen 37 behind it — holds the profile as it was
      // when she tapped, for as long as she keeps it open.
      builder: (_) => StreamBuilder<void>(
        stream: c.changes,
        builder: (_, __) => source == null
            ? screen(widget.catalog)
            : ValueListenableBuilder<ContentCatalog>(
                valueListenable: source,
                builder: (_, catalog, __) => screen(catalog),
              ),
      ),
    ));
  }

  /// Screen 41 — «Магазин».
  ///
  /// The whole offer inside the app. Until now the only way to buy anything was
  /// the landing page in a browser, which a customer who already has the app is
  /// unlikely to be looking at.
  void _openShop(BuildContext context, AppController c) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _ShopRoute(controller: c),
    ));
  }

  /// Screen 42 — «Мой заказ».
  ///
  /// «Написать» opens WhatsApp on the number the admin panel configured. It is
  /// fetched rather than compiled in, and the button is absent when there is
  /// none — a contact button that opens nothing is worse than no button on the
  /// screen somebody reaches when a delivery has gone wrong.
  void _openMyOrder(BuildContext context, AppController c) {
    final api = c.api;
    if (api == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _MyOrderRoute(controller: c),
    ));
  }

  /// Screen 40 — «Семейный доступ».
  ///
  /// Every callback reports what the SERVER answered. A remove that returns
  /// true on a failed request would leave a mother believing she had shut
  /// somebody out of her child's location when she had not.
  void _openFamilyAccess(BuildContext context, AppController c) {
    final api = c.api;
    if (api == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FamilyAccessScreen(
        now: DateTime.now(),
        load: () async => FamilyAccess.fromJson(await api.familyAccess()),
        onInvite: (level, label) async {
          try {
            final r = await api.createFamilyInvite(level: level.wire, label: label);
            final token = r['token'];
            return token is String && token.isNotEmpty ? token : null;
          } catch (_) {
            // Null, so the screen says the link could not be made. Silence
            // here leaves her waiting for one that was never created.
            return null;
          }
        },
        onRemove: (m) => api.removeFamilyMember(m.memberUserId),
        onRevoke: (i) => api.revokeFamilyInvite(i.tokenHash),
        // The other side of the invitation. Without it a relative who was sent
        // a link has nowhere to put the code and the path dead-ends.
        onAccept: (token) async {
          try {
            return await api.acceptFamilyInvite(token);
          } catch (_) {
            return (ok: false, reason: null);
          }
        },
        // The link somebody actually receives. A path on the site rather than
        // a custom scheme, so it opens for a relative who has not installed
        // the app yet — which is most of them, the first time.
        linkFor: (token) => 'https://ana-bala.kz/join/$token',
      ),
    ));
  }

  /// Screen 47 — «История дня» for the selected child.
  ///
  /// The loader THROWS on failure rather than returning null: the screen shows
  /// a failed load differently from an empty day, and it cannot tell the two
  /// apart from a null.
  void _openDayHistory(BuildContext context, AppController c) {
    final api = c.api;
    final child = c.selectedChild;
    if (api == null || child == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DayHistoryScreen(
        childName: c.childName,
        now: DateTime.now(),
        load: (day) async => DayHistory.fromJson(await api.childDay(child.id, day)),
        routeMapBuilder: _buildRouteMap,
        onSaveOutcome: (event, outcome) =>
            api.saveSosOutcome(child.id, event.at, outcome.wire),
      ),
    ));
  }

  /// «Карточка ребёнка» — the child-care hub.
  ///
  /// ChildDetailScreen had exactly one caller in the whole app (Настройки →
  /// Дети), so Медкарта, Прививки, Рост и вес, Развитие, Дневник
  /// новорождённого, Детектор плача, Прикорм, Безопасность дома and Болезни
  /// were all three taps down a settings screen and nowhere else.
  ///
  /// [childId] when the caller already knows which child it means (the map has
  /// a selection). Otherwise: none → the add sheet, one → that one, several →
  /// the picker. Guessing with several opens the wrong child's medical record.
  Future<void> _openChildCard(BuildContext context, AppController c,
      {String? childId}) async {
    var id = childId;
    if (id == null) {
      if (c.children.isEmpty) {
        await showAddChildSheet(context, c);
        return;
      }
      id = c.children.length == 1
          ? c.children.first.id
          : await showPickChildSheet(context, c);
      if (id == null || !context.mounted) return;
    }
    final chosen = id;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChildDetailScreen(controller: c, childId: chosen),
    ));
  }

  /// Open the hand-entry sheet and record whatever comes back. The controller
  /// triages it exactly as it would a band reading, so this may raise the
  /// emergency screen — which is the intended behaviour.
  Future<void> _logVitals(BuildContext context, AppController c) async {
    final api = c.api;
    final reading = await showLogVitalsSheet(
      context,
      // Only offer the photo shortcut when we can reach the server; offline, the
      // sheet is manual-entry only.
      onScan: api == null ? null : (bytes, mediaType) => api.extractVitalsFromImage(bytes, mediaType),
    );
    if (reading == null) return;
    final saved = c.logManualVitals(reading);
    if (!saved || !context.mounted) return;
    final l = L10nScope.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.t('vitals_saved')), behavior: SnackBarBehavior.floating),
    );
  }

  /// Which day of «Аудио дня» belongs to this family, if any.
  ///
  /// Pregnancy wins over a child, the same order every stage decision in this
  /// shell follows. Null when there is neither a due date nor a child with a
  /// birth date — there is no day to ask the server for, and the card would
  /// fetch `/audio/child/0`.
  ({String track, int day})? _audioDay(AppController c) {
    final g = c.isPregnant ? c.gestation : null;
    if (g != null) return (track: 'pregnancy', day: g.totalDays);
    final child = _heroChild(c);
    if (child == null) return null;
    final days = childAgeDays(child.dateOfBirth!, DateTime.now());
    return days >= 1 ? (track: 'child', day: days) : null;
  }

  /// Where this family is on the timeline: their pregnancy week if there is a
  /// due date, otherwise the selected child's age in months.
  TimelineStage? _stageFor(AppController c) => currentStage(
        gestationWeek: c.isPregnant ? c.gestation?.week : null,
        childAgeMonths: c.selectedChild?.hasDateOfBirth == true
            ? c.selectedChild!.ageInMonths(DateTime.now())
            : null,
      );

  /// This stage's shelf, narrowed to what actually applies to her.
  ///
  /// City and birth date are optional, and a profile without them loses nothing
  /// from the baseline — it only misses the extras that depend on knowing, like
  /// a product that ships to one city.
  List<ContentItem> _contentFor(AppController c) {
    final stage = _stageFor(c);
    if (stage == null) return const [];
    final p = c.profile;
    return itemsForViewer(
      widget.catalog.itemsFor(stage),
      ContentViewer(city: p.city, ageYears: p.ageYears(DateTime.now())),
    );
  }

  /// Open a lesson video or a product page in the browser. Items without a URL
  /// are not tappable, so this is only reached for a real link.
  Future<void> _openContent(ContentItem item) async {
    // A lesson we host plays in OUR player, with our controls and no third
    // party's branding. Everything else — a shop page, a YouTube link — leaves
    // the app, which for YouTube is not a limitation but a requirement.
    if (item.playsInApp) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => LessonPlayerScreen(item: item)),
      );
      return;
    }
    final target = item.video?.url ?? item.url;
    final uri = Uri.tryParse(target);
    if (uri == null || target.trim().isEmpty) return;

    // Attempt it and report the result, rather than asking permission first.
    //
    // canLaunchUrl answers "is a handler visible to me", which on Android 11+
    // means "did the manifest declare a <queries> intent for this scheme" —
    // and it did not for https. So this returned false on every modern Android
    // device and the tap did nothing: no browser, no error, no explanation.
    // The manifest is fixed, but gating on that check would leave the same
    // dead-tap failure mode one packaging mistake away.
    final l = L10nScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.t('link_open_failed')), behavior: SnackBarBehavior.floating),
      );
    }
  }

  /// The child the home block is about: the selected one when it has a birth
  /// date, otherwise the first that does. Null when none has one — there is no
  /// age to count from, and guessing is worse than falling through.
  ChildProfile? _heroChild(AppController c) {
    final sel = c.selectedChild;
    if (sel?.dateOfBirth != null) return sel;
    for (final ch in c.children) {
      if (ch.dateOfBirth != null) return ch;
    }
    return null;
  }

  /// «Тест положительный» — she tells the app she is pregnant.
  ///
  /// The design system asks for stage changes to happen as EVENTS rather than
  /// through a date picker, and this one had no entry point anywhere: the only
  /// way to become pregnant in this app was to find «срок родов» in the
  /// calendar and set a date.
  ///
  /// It still needs a due date — every pregnancy calculation is anchored to one
  /// — so it asks for the last period instead, which is the date she actually
  /// knows, and derives the rest. Nothing is saved until she picks.
  Future<void> _recordPositiveTest(BuildContext context, AppController c) async {
    final l = L10nScope.of(context);
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      helpText: l.t('preg_lmp_help'),
      initialDate: c.cycle.lastPeriodStart ?? now.subtract(const Duration(days: 42)),
      // A pregnancy runs 40 weeks from the last period; anything older than
      // that is not a start date, and a future one is a mis-set picker.
      firstDate: now.subtract(const Duration(days: 280)),
      lastDate: now,
    );
    if (picked == null || !context.mounted) return;

    // 280 days from the last period is the standard estimate — the same
    // arithmetic gestationFor already runs in reverse.
    c.setDueDate(picked.add(const Duration(days: 280)));
    if (!context.mounted) return;
    // Land her on the calendar, which is now the pregnancy one: the change is
    // large enough that showing it beats announcing it.
    setState(() => _index = 1);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l.t('preg_started'))));
  }

  /// Open the sleep sheet and record the night. Unlike band summaries this is
  /// persisted, so it survives a restart — nothing else would re-supply it.
  Future<void> _logSleep(BuildContext context, AppController c) async {
    final entry = await showLogSleepSheet(context, now: DateTime.now());
    if (entry == null) return;
    final saved = c.logManualSleep(entry);
    if (!saved || !context.mounted) return;
    final l = L10nScope.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.t('sleep_logged')), behavior: SnackBarBehavior.floating),
    );
  }

  /// A short chip label for the dashboard: pregnancy week or cycle day. Empty
  /// when there's no cycle/pregnancy data yet (chip hidden).
  String _statusChip(AppController c, L10n l) {
    if (c.isPregnant) {
      final g = c.gestation;
      return g != null ? l.t('db_chip_pregnancy', {'n': g.week}) : '';
    }
    final cyc = c.cycle;
    if (!cyc.hasData || cyc.cycleDay == null) return '';
    // A late period is the thing most worth surfacing — say so instead of
    // burying it behind a cycle-day number.
    final until = cyc.daysUntilNextPeriod;
    if (cyc.isPredictedLate && until != null) return l.t('db_chip_late', {'n': -until});
    return l.t('db_chip_cycle', {'n': cyc.cycleDay});
  }

  /// Whether the cycle chip should read as "worth a look" (amber) rather than
  /// routine. Pregnancy is never late.
  bool _statusChipLate(AppController c) => !c.isPregnant && c.cycle.isPredictedLate;

  /// Screen 38 · take her to the thing the notification was about.
  ///
  /// Every branch lands somewhere real. `dashboard` is the deliberate fallback
  /// for anything this build does not recognise — a `screen` from a newer
  /// server, a payload that is not JSON — because the alternative a tapped
  /// notification must never have is nothing happening.
  ///
  /// SOS is absent on purpose: it is a takeover raised over the whole app by
  /// AppController, not a route pushed on this shell.
  void _goTo(NotifyDestination d, AppController c) {
    switch (d) {
      case NotifyDestination.supportThread:
        // Screen 43. Without a server there is no thread to show, so fall back
        // to the profile tab, which is where Настройки → Помощь lives.
        if (c.api != null) {
          openSupportThread(context, c);
        } else {
          setState(() => _index = _tabDashboard);
        }
      case NotifyDestination.notificationCentre:
        _openNotificationCentre(context, c);
      case NotifyDestination.childMap:
        setState(() => _index = _tabChild);
      case NotifyDestination.sos:
      case NotifyDestination.emergency:
      // Both are app-wide takeovers raised by the controller; if one is not
      // latched by the time this runs there is nothing left to show, and the
      // dashboard is the honest destination.
      case NotifyDestination.dashboard:
        setState(() => _index = _tabDashboard);
    }
  }

  /// Screen 39 — «Центр уведомлений». A method rather than a closure
  /// because a tapped рассылка has to open the same screen the bell does.
  void _openNotificationCentre(BuildContext context, AppController c) {
          // Fetch on open, like the support row does before it draws its badge.
          // The screen still paints from what the controller already holds — it
          // never waits on the network — but a рассылка published while she had
          // the app open reaches her here rather than at the next cold launch.
          c.refreshAnnouncements();
          Navigator.of(context).push(MaterialPageRoute(
            // Rebuilt on every controller change, so the answer to that fetch
            // lands on the open screen rather than behind it. Pushed routes sit
            // outside the shell's StreamBuilder: without this the centre would
            // read the list once, at the instant of the tap, and the message
            // that arrives a second later would wait for her next visit.
            builder: (_) => StreamBuilder<void>(
              stream: c.changes,
              builder: (_, __) => NotificationCentreScreen(
                alerts: c.alerts,
                // Screen 39's other half: what the back office sent her (admin
                // frame 06). Same list, same «Прочитать всё», same watermark —
                // she has one inbox, not two.
                announcements: c.announcements,
                now: DateTime.now(),
                readUpTo: c.alertsReadUpTo,
                onReadAll: c.markAlertsRead,
                // Screen 25 — the reminders centre, including quiet hours. The
                // comment here said it "does not exist yet" and hid the button;
                // it has existed for some time and is reachable from Settings,
                // so the one screen about notifications had no route to the
                // screen that configures them.
                onConfigure: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => RemindersCenterScreen(controller: c)),
                ),
                // The old alerts view, kept for what it alone does: per-child
                // counts and «сколько дней без SOS». Reached from here rather
                // than left unreferenced — deleting a working screen to tidy an
                // import is worse than either.
                onOpenStats: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => AlertsScreen(controller: c)),
                ),
              ),
            ),
          ));
  }

  /// The child marker + geofence circles. The map itself lives in
  /// tracking_map.dart, because screen 21 shows the same thing.
  Widget _buildMap(BuildContext context, Coordinates? child, List<Geofence> fences) =>
      buildTrackingMap(context, child, fences);
}

/// Screen 41, with its WhatsApp number resolved before the screen is built.
///
/// Same reason as screen 42: the number decides whether the buy BUTTONS exist,
/// and a shop that grows its buy buttons a second after opening is one somebody
/// taps by accident.
class _ShopRoute extends StatefulWidget {
  final AppController controller;
  const _ShopRoute({required this.controller});

  @override
  State<_ShopRoute> createState() => _ShopRouteState();
}

class _ShopRouteState extends State<_ShopRoute> {
  String _whatsapp = '';

  /// What is actually for sale, at today's prices. [ShopCatalogue.empty] when
  /// the shop could not be reached and nothing was cached — the screen then
  /// shows the compile-time constants and says they are approximate.
  ShopCatalogue _catalogue = ShopCatalogue.empty;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Both before the first paint, and for the same reason: the number decides
    // whether buy buttons exist and the catalogue decides what they say (an
    // out-of-stock product asks «под заказ»). A screen that rewrites its own
    // buttons a second in is one somebody taps by accident.
    //
    // Neither call throws — getShopCatalogue degrades to its cache and then to
    // nothing — so there is no failure branch to handle here beyond what the
    // screen already renders.
    final api = widget.controller.api;
    final contact = await api?.getShopContact();
    final catalogue = await api?.getShopCatalogue();
    if (!mounted) return;
    setState(() {
      _whatsapp = contact?.whatsapp ?? '';
      _catalogue = catalogue ?? ShopCatalogue.empty;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const HomeSkeleton();
    }
    final c = widget.controller;
    final digits = _whatsapp.replaceAll(RegExp(r'\D'), '');
    final now = DateTime.now();
    return ShopScreen(
      pregnant: c.isPregnant,
      childAgesMonths: [
        for (final ch in c.children)
          if (ch.hasDateOfBirth) ch.ageInMonths(now),
      ],
      catalogue: _catalogue,
      onOrder: digits.isEmpty
          ? null
          : (message) => launchUrl(
                Uri.parse(
                    'https://wa.me/$digits?text=${Uri.encodeComponent(message)}'),
                mode: LaunchMode.externalApplication,
              ),
    );
  }
}

/// Screen 42, with its WhatsApp number resolved before the screen is built.
///
/// A small stateful wrapper rather than a FutureBuilder inside the screen: the
/// number decides whether a BUTTON exists, and a screen that grows a contact
/// button a second after it opens is one somebody taps by accident.
class _MyOrderRoute extends StatefulWidget {
  final AppController controller;
  const _MyOrderRoute({required this.controller});

  @override
  State<_MyOrderRoute> createState() => _MyOrderRouteState();
}

class _MyOrderRouteState extends State<_MyOrderRoute> {
  String _whatsapp = '';
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final contact = await widget.controller.api?.getShopContact();
    if (!mounted) return;
    setState(() {
      _whatsapp = contact?.whatsapp ?? '';
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final api = widget.controller.api;
    if (!_ready || api == null) {
      return const ListSkeleton();
    }
    final digits = _whatsapp.replaceAll(RegExp(r'\D'), '');
    return MyOrderScreen(
      load: () async => MyOrders.fromJson(await api.myOrders()),
      onCancel: (o) => api.cancelMyOrder(o.orderId),
      onWrite: digits.isEmpty
          ? null
          : () => launchUrl(
                Uri.parse('https://wa.me/$digits'),
                mode: LaunchMode.externalApplication,
              ),
      // The only fix for a missing number is the profile editor.
      onAddPhone: () {
        Navigator.of(context).pop();
        showEditProfileSheet(context, widget.controller);
      },
    );
  }
}

/// The day's route, for screen 47.
///
/// A polyline through the thinned points with a dot at each, and a distinct
/// marker where an SOS was pressed. Camera on the first point rather than on
/// the child's current position: this screen is about where she WAS.
Widget _buildRouteMap(
  BuildContext context,
  List<RoutePoint> points,
  List<DayEvent> events,
) {
  if (!kMapsEnabled) {
    return const MapPlaceholder(fences: [], child: null);
  }
  // The first point of the day; failing that, an event that carries a
  // position (screen 48 opens with no trail at all, only the SOS); failing
  // that, Almaty, the same fallback the live map uses.
  final located = events.where((e) => e.lat != null && e.lng != null);
  final anchor = points.isNotEmpty
      ? LatLng(points.first.lat, points.first.lng)
      : located.isNotEmpty
          ? LatLng(located.first.lat!, located.first.lng!)
          : const LatLng(43.238949, 76.889709);
  return GoogleMap(
    initialCameraPosition: CameraPosition(target: anchor, zoom: 14),
    myLocationButtonEnabled: false,
    polylines: {
      if (points.length >= 2)
        Polyline(
          polylineId: const PolylineId('route'),
          width: 4,
          color: Palette.violet,
          points: [for (final p in points) LatLng(p.lat, p.lng)],
        ),
    },
    markers: {
      for (final (i, p) in points.indexed)
        Marker(
          markerId: MarkerId('p$i'),
          position: LatLng(p.lat, p.lng),
          // Only the ends are labelled. A tooltip on every one of forty points
          // is a map you cannot tap through.
          infoWindow: i == 0 || i == points.length - 1
              ? InfoWindow(title: '${p.at.hour}:${p.at.minute.toString().padLeft(2, '0')}')
              : InfoWindow.noText,
        ),
      for (final (i, e) in events.indexed)
        if (e.kind == DayEventKind.sos && e.lat != null && e.lng != null)
          Marker(
            markerId: MarkerId('sos$i'),
            position: LatLng(e.lat!, e.lng!),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          ),
    },
  );
}


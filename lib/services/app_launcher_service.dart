// app_launcher_service.dart

import 'package:android_intent_plus/android_intent.dart';
import 'package:device_apps/device_apps.dart';

class AppLauncherService {
  // ─── Known package map (add more as needed) ────────────────────────────────
  static const Map<String, String> _knownApps = {
    // Social
    'whatsapp'        : 'com.whatsapp',
    'instagram'       : 'com.instagram.android',
    'facebook'        : 'com.facebook.katana',
    'snapchat'        : 'com.snapchat.android',
    'twitter'         : 'com.twitter.android',
    'x'               : 'com.twitter.android',
    // FIX: 'telegram x' was mapped to org.instagram.barcelona (Threads) — wrong.
    // Telegram X is a third-party Telegram client by Telegram LLC.
    'telegram x'      : 'org.thunderdog.challegram',
    'telegram'        : 'org.telegram.messenger',
    'linkedin'        : 'com.linkedin.android',
    'tiktok'          : 'com.zhiliaoapp.musically',
    'discord'         : 'com.discord',
    'pinterest'       : 'com.pinterest',
    'reddit'          : 'com.reddit.frontpage',
    // FIX: 'threads' correctly maps to com.instagram.barcelona (Meta Threads app)
    'threads'         : 'com.instagram.barcelona',

    // Google
    'youtube'         : 'com.google.android.youtube',
    'maps'            : 'com.google.android.apps.maps',
    'google maps'     : 'com.google.android.apps.maps',
    'gmail'           : 'com.google.android.gm',
    'calendar'        : 'com.google.android.calendar',
    'photos'          : 'com.google.android.apps.photos',
    'google photos'   : 'com.google.android.apps.photos',
    'drive'           : 'com.google.android.apps.docs',
    'google drive'    : 'com.google.android.apps.docs',
    'meet'            : 'com.google.android.apps.tachyon',
    'google meet'     : 'com.google.android.apps.tachyon',
    'play store'      : 'com.android.vending',
    'messages'        : 'com.google.android.apps.messaging',
    'files'           : 'com.google.android.apps.nbu.files',
    'chrome'          : 'com.android.chrome',
    'google'          : 'com.google.android.googlequicksearchbox',
    'sheets'          : 'com.google.android.apps.docs.editors.sheets',
    'docs'            : 'com.google.android.apps.docs.editors.docs',
    'slides'          : 'com.google.android.apps.docs.editors.slides',
    'keep'            : 'com.google.android.keep',
    'translate'       : 'com.google.android.apps.translate',
    'pay'             : 'com.google.android.apps.nbu.paisa.user',
    'google pay'      : 'com.google.android.apps.nbu.paisa.user',
    'news'            : 'com.google.android.apps.magazines',
    'fit'             : 'com.google.android.apps.fitness',
    'duo'             : 'com.google.android.apps.tachyon',
    'assistant'       : 'com.google.android.googlequicksearchbox',
    'gemini'          : 'com.google.android.apps.bard',

    // System
    'settings'        : 'com.android.settings',
    'camera'          : 'com.android.camera2',
    'phone'           : 'com.android.dialer',
    'dialer'          : 'com.android.dialer',
    'contacts'        : 'com.android.contacts',
    'calculator'      : 'com.android.calculator2',
    'clock'           : 'com.android.deskclock',
    'alarm'           : 'com.android.deskclock',
    'gallery'         : 'com.android.gallery3d',
    'music'           : 'com.android.music',
    'browser'         : 'com.android.browser',
    'notes'           : 'com.google.android.keep',
    'recorder'        : 'com.android.soundrecorder',
    'downloads'       : 'com.android.documentsui',

    // Streaming
    'netflix'         : 'com.netflix.mediaclient',
    'spotify'         : 'com.spotify.music',
    'prime video'     : 'com.amazon.avod.thirdpartyclient',
    'amazon prime'    : 'com.amazon.avod.thirdpartyclient',
    'hotstar'         : 'in.startv.hotstar',
    'disney'          : 'in.startv.hotstar',
    'disney hotstar'  : 'in.startv.hotstar',
    'zee5'            : 'com.zee5.app',
    'sony liv'        : 'com.sonyliv',
    'sonyliv'         : 'com.sonyliv',
    'jio cinema'      : 'com.jio.jiocinema',
    'mxplayer'        : 'com.mxtech.videoplayer.ad',
    'vlc'             : 'org.videolan.vlc',
    'gaana'           : 'com.gaana',
    'wynk'            : 'com.bsb.mango',

    // Shopping
    'amazon'          : 'com.amazon.mShop.android.shopping',
    'flipkart'        : 'com.flipkart.android',
    'myntra'          : 'com.myntra.android',
    'meesho'          : 'com.meesho.supply',
    'nykaa'           : 'com.fsn.nykaa',
    'ajio'            : 'com.ril.ajio',
    'snapdeal'        : 'com.snapdeal.main',

    // Finance & Payments
    'paytm'           : 'net.one97.paytm',
    'phonepe'         : 'com.phonepe.app',
    'gpay'            : 'com.google.android.apps.nbu.paisa.user',
    'bhim'            : 'in.org.npci.upiapp',
    'cred'            : 'com.dreamplug.androidapp',
    'groww'           : 'com.nextbillion.groww',
    'zerodha'         : 'com.zerodha.kite3',

    // Travel
    'ola'             : 'com.olacabs.customer',
    'uber'            : 'com.ubercab',
    'rapido'          : 'com.rapido.passenger',
    'irctc'           : 'cris.org.in.prs.ima',
    'makemytrip'      : 'com.makemytrip',
    'redbus'          : 'in.redbus.android',

    // Food
    'swiggy'          : 'in.swiggy.android',
    'zomato'          : 'com.application.zomato',
    'blinkit'         : 'com.grofers.customerapp',
    'dunzo'           : 'com.dunzo.user',
    'instamart'       : 'in.swiggy.android',
    'bigbasket'       : 'com.bigbasket',

    // Work & Productivity
    'zoom'            : 'us.zoom.videomeetings',
    'teams'           : 'com.microsoft.teams',
    'slack'           : 'com.Slack',
    'notion'          : 'notion.id',
    'word'            : 'com.microsoft.office.word',
    'excel'           : 'com.microsoft.office.excel',
    'powerpoint'      : 'com.microsoft.office.powerpoint',
    'outlook'         : 'com.microsoft.office.outlook',
    'onedrive'        : 'com.microsoft.skydrive',
    'one drive'       : 'com.microsoft.skydrive',
    'dropbox'         : 'com.dropbox.android',
    'trello'          : 'com.trello',
    'asana'           : 'com.asana.app',

    // Health
    'healthify'       : 'com.healthifyme.basic',
    'stepsetgo'       : 'io.stepsetgo.app',
    'cult fit'        : 'com.curefit.main',
    'practo'          : 'com.practo.fabric',

    // News
    'inshorts'        : 'com.inshorts.reader',
    'times of india'  : 'com.toi.reader.activities',
    'cricbuzz'        : 'com.cricbuzz.android',
    'espncricinfo'    : 'com.espn.cricket',

    // Other
    'phonepe business': 'com.phonepe.business',
    'truecaller'      : 'com.truecaller',
    '1password'       : 'com.agilebits.onepassword',
    'lastpass'        : 'com.lastpass.lpandroid',
    'tasker'          : 'net.dinglisch.android.taskerm',
  };

  // ─── Open app by spoken name ───────────────────────────────────────────────
  Future<bool> openAppByName(String spokenName) async {
    final lower = spokenName.toLowerCase().trim();

    // 1. Exact match
    if (_knownApps.containsKey(lower)) {
      return DeviceApps.openApp(_knownApps[lower]!);
    }

    // 2. Partial match in known map
    for (final entry in _knownApps.entries) {
      if (lower.contains(entry.key) || entry.key.contains(lower)) {
        return DeviceApps.openApp(entry.value);
      }
    }

    // 3. Scan installed apps on device
    final apps = await DeviceApps.getInstalledApplications(
      includeSystemApps: true,
      onlyAppsWithLaunchIntent: true,
    );

    Application? best;
    for (final app in apps) {
      final appLower = app.appName.toLowerCase();
      if (appLower == lower || appLower.contains(lower) || lower.contains(appLower)) {
        best = app;
        break;
      }
    }

    if (best != null) {
      return DeviceApps.openApp(best.packageName);
    }

    return false; // not found
  }

  // ─── Camera (direct intent) ───────────────────────────────────────────────
  Future<void> openCamera() async {
    final intent = AndroidIntent(action: 'android.media.action.IMAGE_CAPTURE');
    await intent.launch();
  }

  // ─── Settings (direct intent) ─────────────────────────────────────────────
  Future<void> openSettings() async {
    final intent = AndroidIntent(action: 'android.settings.SETTINGS');
    await intent.launch();
  }
}
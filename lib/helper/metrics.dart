import 'dart:convert';
import 'dart:io';

import 'package:covidtrace/config.dart';
import 'package:covidtrace/state.dart';
import 'package:flutter_safetynet_attestation/flutter_safetynet_attestation.dart';
import 'package:gact_plugin/gact_plugin.dart';
import 'package:google_api_availability/google_api_availability.dart' as ga;
import 'package:http/http.dart' as http;
import 'package:package_info/package_info.dart';
import 'package:uuid/uuid.dart';

Future<http.Response> report(Map<String, dynamic> postData) async {
  Map<String, dynamic> config;
  try {
    config = await Config.remote();
  } catch (err) {
    print('Unable to fetch remote config');
    return null;
  }

  // Silently ignore unconfigured metric reporting
  if (!config.containsKey('metricsPublishUrl')) {
    print('Metric reporting is not configured');
    return null;
  }

  var user = AppState.instance.user;
  var deviceId =
      user.deviceId ?? DateTime.now().millisecondsSinceEpoch.toString();

  // Add deviceCheck or Attestation to payload depending on platform
  if (Platform.isIOS) {
    try {
      deviceId = await GactPlugin.deviceCheck;
    } catch (err) {
      print('metric deviceCheck error');
      print(err);
    }
    postData['deviceCheck'] = deviceId;
  }

  if (Platform.isAndroid) {
    try {
      var available = await ga.GoogleApiAvailability.instance
          .checkGooglePlayServicesAvailability(false);

      if (available != ga.GooglePlayServicesAvailability.success) {
        return null;
      }

      var nonce = Uuid().v4();
      deviceId =
          await FlutterSafetynetAttestation.safetyNetAttestationJwt(nonce);
    } catch (err) {
      print('metric attestation error');
      print(err);
    }
    postData['deviceAttestation'] = deviceId;
  }

  postData['version'] = (await PackageInfo.fromPlatform()).version;
  print(postData);

  var url = config['metricsPublishUrl'];
  var postResp;
  try {
    postResp = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(postData),
    );

    if (postResp.statusCode != 200) {
      print('Metric reporting error ${postResp.statusCode}');
      print(postResp.body);
    }
  } catch (err) {
    print('Unable to report metric: ${jsonEncode(postData)}');
    print(err);
  }

  user.deviceId = deviceId;
  await AppState.instance.saveUser(user);

  return postResp;
}

Future install() {
  return report({
    "event": "install",
  });
}

Future onboard({bool authorized = false, bool notifications = false}) {
  return report({
    "event": "onboard",
    "payload": {
      "en_enabled": authorized,
      "notifications_enabled": notifications,
    }
  });
}

Future exposure() {
  return report({
    "event": "exposure",
  });
}

Future contact() {
  return report({
    "event": "contact",
  });
}

Future notify() {
  return report({
    "event": "notify",
  });
}

Future check(bool background, {int delay = 0}) {
  return report({
    "event": "check",
    "payload": {"bg": background, "delay": delay}
  });
}

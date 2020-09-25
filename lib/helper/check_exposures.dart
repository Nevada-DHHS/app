import 'dart:async';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:covidtrace/config.dart';
import 'package:covidtrace/helper/metrics.dart' as metrics;
import 'package:covidtrace/state.dart';
import 'package:covidtrace/storage/exposure.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:gact_plugin/gact_plugin.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pool/pool.dart';

bool checkingExposures = false;

Future<List<Uri>> processKeyIndexFile(
  String url,
  Directory dir,
) async {
  print('processing export key index file $url');

  var indexFile = await http.get(url);
  if (indexFile.statusCode != 200) {
    return null;
  }

  var user = AppState.instance.user;
  var lastKeyFile = user.lastKeyFile ?? '';
  // Filter objects for any that are lexically equal to or greater than
  // the last downloaded batch. If we have never checked before, we
  // should fetch everything in the index.
  var exportFiles = indexFile.body
      .split('\n')
      .where((name) => name.compareTo(lastKeyFile) > 0);

  if (exportFiles.isEmpty) {
    print('No new keys to check!');
    return [];
  }

  user.lastKeyFile = exportFiles.last;
  await user.save();

  var parsed = Uri.parse(url);
  var path = parsed.pathSegments;
  var keyFiles = await downloadExposureKeyFiles(exportFiles.map((fileName) {
    // Note that export zip files are always in the same directory as the index file
    // and that the index file has entries like so:
    // "/exposure-key-index-dir/path-to-export-file.zip"
    return '${parsed.origin}/${path.sublist(0, path.length - 2).join('/')}/$fileName';
  }), dir);

  return keyFiles;
}

Future<List<Uri>> downloadExposureKeyFiles(
    Iterable<String> exportFiles, Directory dir) async {
  var pool = new Pool(15, timeout: new Duration(seconds: 120));
  var downloads = await Future.wait(exportFiles.map((object) {
    return pool.withResource(() async {
      print('Downloading $object');
      // Download each exported zip file
      var response = await http.get(object);
      if (response.statusCode != 200) {
        print(response.body);
        return null;
      }

      var keyFile = File('${dir.path}/exposures${Uri.parse(object).path}');
      if (!await keyFile.exists()) {
        await keyFile.create(recursive: true);
      }
      return keyFile.writeAsBytes(response.bodyBytes);
    });
  }));

  // Decompress and verify downloads
  List<List<Uri>> keyFiles = await Future.wait(downloads.map((File file) {
    return pool.withResource(() async {
      if (Platform.isAndroid) {
        return [file.uri];
      }

      var archive = ZipDecoder().decodeBytes(await file.readAsBytes());
      var first = archive.files[0];
      var second = archive.files[1];

      var bin = first.name == 'export.bin' ? first : second;
      var sig = first.name == 'export.sig' ? first : second;

      // Save files to disk
      var binFile = File('${file.path}.bin');
      var sigFile = File('${file.path}.sig');

      if (!await binFile.exists()) {
        await binFile.create(recursive: true);
      }
      await binFile.writeAsBytes(bin.content as List<int>);

      if (!await sigFile.exists()) {
        await sigFile.create(recursive: true);
      }
      await sigFile.writeAsBytes(sig.content as List<int>);
      return [binFile.uri, sigFile.uri];
    });
  }));

  print('Done decompressing downloaded files');

  return keyFiles.expand((files) => files).toList();
}

Future<List<ExposureInfo>> detectExposures(
    List<Uri> keyFiles, Map<String, dynamic> exposureConfig) async {
  await GactPlugin.setExposureConfiguration(exposureConfig);

  await GactPlugin.setUserExplanation(
      'You were in close proximity to someone who tested positive for COVID-19.');

  // Save all found exposures
  List<ExposureInfo> exposures;
  try {
    var minRiskScore = exposureConfig['minimumRiskScore'];
    var summary = await GactPlugin.detectExposures(keyFiles);
    if (summary.maximumRiskScore < minRiskScore) {
      return [];
    }

    exposures = (await GactPlugin.getExposureInfo())
        .where((info) => info.totalRiskScore >= minRiskScore)
        .toList();

    print('Found ${exposures.length} exposure keys that match min risk score');

    await Future.wait(exposures.map((e) {
      return ExposureModel(
        date: e.date,
        duration: e.duration,
        totalRiskScore: e.totalRiskScore,
        transmissionRiskLevel: e.transmissionRiskLevel,
      ).insert();
    }));
  } catch (err) {
    print(err);
    return [];
  } finally {
    // Cleanup downloaded files
    await Future.wait(keyFiles.map((file) => File(file.toFilePath()).delete()));
  }

  return exposures;
}

Future<ExposureInfo> checkExposures({bool background = true}) async {
  if (checkingExposures) {
    return null;
  }
  checkingExposures = true;

  print('Checking exposures...');
  if (!AppState.instance.ready) {
    await AppState.instance.refresh();
  }

  var user = AppState.instance.user;
  var now = DateTime.now();
  metrics.check(background,
      delay: user.lastCheck != null
          ? now.difference(user.lastCheck).inMilliseconds
          : 0);

  var results = await Future.wait([
    Config.remote(),
    getApplicationSupportDirectory(),
  ]);

  var config = results[0] as Map<String, dynamic>;
  var dir = results[1] as Directory;

  String indexFileUrl;

  // Prefer new config value since it's more flexible in specifying a
  // destination that isn't tied to Google Storage
  if (config.containsKey('exposureKeysIndexUrl')) {
    indexFileUrl = config['exposureKeysIndexUrl'];
  } else {
    String publishedBucket = config['exposureKeysPublishedBucket'];
    String indexFileName = config['exposureKeysPublishedIndexFile'];
    indexFileUrl =
        'https://$publishedBucket.storage.googleapis.com/$indexFileName';
  }
  var keyFiles = await processKeyIndexFile(indexFileUrl, dir) ?? [];

  List<ExposureInfo> exposures = [];
  if (keyFiles.isNotEmpty) {
    exposures = await detectExposures(
        keyFiles, config['exposureNotificationConfiguration']);
  }

  user.lastCheck = now;
  await AppState.instance.saveUser(user);

  exposures.sort((a, b) => a.date.compareTo(b.date));
  var exposure = exposures.isNotEmpty ? exposures.last : null;

  checkingExposures = false;
  print('Done checking exposures!');

  if (exposure != null) {
    metrics.exposure();
  }

  if (background) {
    AppState.instance.refresh();
  }

  return exposure;
}

void showExposureNotification(ExposureInfo exposure, {Duration delay}) async {
  var date = exposure.date.toLocal();
  var dur = exposure.duration;
  var notificationPlugin = FlutterLocalNotificationsPlugin();
  var config = Config.get();

  var androidSpec = AndroidNotificationDetails(
      '1', config['theme']['title'], 'Exposure notifications',
      importance: Importance.Max, priority: Priority.High, ticker: 'ticker');
  var iosSpecs = IOSNotificationDetails();

  var id = 0;
  var title = 'COVID-19 Exposure Alert';
  var body =
      'On ${DateFormat.EEEE().add_MMMd().format(date)} you were in close proximity to someone for ${dur.inMinutes} minutes who tested positive for COVID-19.';
  var details = NotificationDetails(androidSpec, iosSpecs);
  var payload = 'Default_Sound';

  if (delay != null) {
    await notificationPlugin.schedule(
        id, title, body, DateTime.now().add(delay), details,
        payload: payload);
  } else {
    await notificationPlugin.show(id, title, body, details, payload: payload);
  }
}

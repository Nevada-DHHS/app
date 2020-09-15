import 'dart:async';
import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:covidtrace/config.dart';
import 'package:covidtrace/info_card.dart';
import 'package:covidtrace/helper/metrics.dart' as metrics;
import 'package:covidtrace/privacy_policy.dart';
import 'package:gact_plugin/gact_plugin.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:share/share.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:covidtrace/intl.dart' as locale;
import 'package:provider/provider.dart';
import 'state.dart';

class Dashboard extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => DashboardState();
}

class DashboardState extends State with TickerProviderStateMixin {
  bool _refreshing = false;

  void initState() {
    super.initState();
    loadConfig();
  }

  void loadConfig() async {
    await Config.remote();
    setState(() {
      // Force rebuild to pick up remote overrides
    });
  }

  Future<void> refreshExposures(AppState state) async {
    await state.checkStatus();

    if (state.status != AuthorizationStatus.Authorized) {
      return;
    }

    setState(() {
      _refreshing = true;
    });

    var error;
    try {
      await state.checkExposures();
    } catch (err) {
      error = 'errors.no_connection';
    }

    setState(() {
      _refreshing = false;
    });

    if (error != null) {
      var intl = locale.Intl.of(context);
      Scaffold.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(intl.get('status.exposure.check.error',
              args: [intl.get(error.trim())]))));
    }
  }

  Future<void> refreshStatus(AppState state) async {
    state.checkStatus();
  }

  void enableExposureNotifications(AppState state) async {
    if (state.status == AuthorizationStatus.Unsupported && Platform.isAndroid) {
      launch(Config.get()['support']['gps_link']);
      return;
    }

    try {
      await GactPlugin.enableExposureNotification();
      refreshStatus(state);
    } catch (err) {
      print(err);
      AppSettings.openAppSettings();
    }
  }

  void aboutApp() {
    launch(Config.get()['healthAuthority']['link']);
  }

  void shareApp() {
    Share.share(Config.get()['support']
        [Platform.isIOS ? 'app_link_ios' : 'app_link_android']);
  }

  @override
  Widget build(BuildContext context) {
    var textTheme = Theme.of(context).textTheme;
    var subhead = Theme.of(context)
        .textTheme
        .subtitle1
        .merge(TextStyle(fontWeight: FontWeight.bold));

    var config = Config.get();
    var authority = config["healthAuthority"];
    var theme = config['theme']['dashboard'];
    var faqs = config["faqs"];
    var intl = locale.Intl.of(context);

    var heading = (String title) => [
          SizedBox(height: 20),
          Center(
              child:
                  Text(intl.get(authority['name']), style: textTheme.caption)),
          SizedBox(height: 10),
          Center(child: Text(title, style: subhead)),
          SizedBox(height: 10),
        ];

    var aboutCard = () {
      return Card(
        margin: EdgeInsets.zero,
        child: Column(
          children: [
            InkWell(
              onTap: () => aboutApp(),
              child: Padding(
                padding: EdgeInsets.all(15),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        intl.get(config['about']['title']),
                        style: Theme.of(context)
                            .textTheme
                            .subtitle1
                            .merge(TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 5),
                      child: Image.asset(config['about']['icon'],
                          color: Theme.of(context).primaryColor, height: 30),
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 0, indent: 15, endIndent: 15),
            InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    fullscreenDialog: true, builder: (ctx) => PrivacyPolicy()),
              ),
              child: Padding(
                padding: EdgeInsets.all(15),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        intl.get('status.all.privacy.title'),
                        style: Theme.of(context)
                            .textTheme
                            .subtitle1
                            .merge(TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 5),
                      child: Image.asset('assets/shield_icon.png',
                          color: Theme.of(context).primaryColor, height: 30),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    };

    var shareCard = () {
      return Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: () => shareApp(),
          child: Padding(
            padding: EdgeInsets.all(15),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        intl.get(config['share']['title']),
                        style: Theme.of(context)
                            .textTheme
                            .subtitle1
                            .merge(TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      SizedBox(height: 5),
                      Text(intl.get(config['share']['body'])),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 5),
                  child: Image.asset(config['share']['icon'],
                      color: Theme.of(context).primaryColor, height: 30),
                ),
              ],
            ),
          ),
        ),
      );
    };

    return Consumer<AppState>(builder: (context, state, _) {
      var intl = locale.Intl.of(context);
      var lastCheck = state.user.lastCheck;

      var bgColor = Color(int.parse(theme['not_authorized_background']));
      var textColor = Color(int.parse(theme['not_authorized_text']));
      var alertText = TextStyle(color: textColor);

      var status = state.status;
      if (status != AuthorizationStatus.Authorized) {
        return Padding(
            padding: EdgeInsets.only(left: 15, right: 15),
            child: RefreshIndicator(
              onRefresh: () => refreshStatus(state),
              child: ListView(children: [
                SizedBox(height: 15),
                InkWell(
                  onTap: () => enableExposureNotifications(state),
                  child: Container(
                    decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(10)),
                    child: Padding(
                      padding: EdgeInsets.all(15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(
                                        intl.get(
                                            'status.exposure_disabled.notice.title'),
                                        style: Theme.of(context)
                                            .textTheme
                                            .headline6
                                            .merge(alertText)),
                                  ])),
                              Image.asset('assets/virus_slash_icon.png',
                                  height: 40, color: textColor),
                            ],
                          ),
                          Divider(height: 20, color: textColor),
                          Text(intl.get('status.exposure_disabled.notice.body'),
                              style: alertText)
                        ],
                      ),
                    ),
                  ),
                ),
                ...heading(intl.get('status.non_exposure.faqs.title')),
                shareCard(),
                SizedBox(height: 10),
                ...faqs["non_exposure"].map((item) => InfoCard(item: item)),
                SizedBox(height: 10),
                aboutCard(),
                SizedBox(height: 20),
              ]),
            ));
      }

      bgColor = Color(int.parse(theme['non_exposure_background']));
      textColor = Color(int.parse(theme['non_exposure_text']));
      alertText = TextStyle(color: textColor);

      var exposure = state.exposure;
      if (exposure == null) {
        return Padding(
          padding: EdgeInsets.only(left: 15, right: 15),
          child: RefreshIndicator(
            onRefresh: () => refreshExposures(state),
            child: ListView(children: [
              SizedBox(height: 15),
              InkWell(
                onTap: () => refreshExposures(state),
                child: Container(
                  decoration: BoxDecoration(
                      color: bgColor, borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: EdgeInsets.all(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(
                                      intl.get(
                                          'status.non_exposure.notice.title'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .headline6
                                          .merge(alertText)),
                                ])),
                            Image.asset('assets/people_arrows_icon.png',
                                height: 40, color: textColor),
                          ],
                        ),
                        Divider(height: 20, color: textColor),
                        Row(children: [
                          Expanded(
                              child: Text(
                                  intl.get(
                                      'status.non_exposure.notice.last_check',
                                      args: [
                                        DateFormat.jm()
                                            .format(lastCheck ?? DateTime.now())
                                            .toLowerCase()
                                      ]),
                                  style: alertText)),
                          _refreshing
                              ? Container(
                                  width: 25,
                                  height: 25,
                                  padding: EdgeInsets.all(5),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    backgroundColor: textColor,
                                  ),
                                )
                              : Icon(Icons.refresh, color: textColor, size: 25),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
              ...heading(intl.get('status.non_exposure.faqs.title')),
              shareCard(),
              SizedBox(height: 10),
              ...faqs["non_exposure"].map((item) => InfoCard(item: item)),
              SizedBox(height: 10),
              aboutCard(),
              SizedBox(height: 20),
            ]),
          ),
        );
      }

      bgColor = Color(int.parse(theme['exposure_background']));
      textColor = Color(int.parse(theme['exposure_text']));
      alertText = TextStyle(color: textColor);

      return Padding(
        padding: EdgeInsets.only(left: 15, right: 15),
        child: RefreshIndicator(
          onRefresh: () => refreshExposures(state),
          child: ListView(children: [
            SizedBox(height: 15),
            Container(
              decoration: BoxDecoration(
                  color: bgColor, borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: EdgeInsets.all(15),
                child: Column(children: [
                  Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(intl.get('status.exposure.notice.title'),
                              style: Theme.of(context)
                                  .textTheme
                                  .headline6
                                  .merge(alertText)),
                          SizedBox(height: 2),
                          Text(
                              intl.get('status.exposure.notice.date', args: [
                                DateFormat.EEEE()
                                    .add_MMMd()
                                    .format(exposure.date)
                              ]),
                              style: alertText)
                        ])),
                    Image.asset('assets/shield_virus_icon.png',
                        height: 40, color: textColor),
                  ]),
                  Divider(height: 20, color: textColor),
                  Text(
                      intl.get('status.exposure.notice.body',
                          args: [exposure.duration.inMinutes.toString()]),
                      style: alertText)
                ]),
              ),
            ),
            ...heading(intl.get('status.exposure.faqs.title')),
            if (authority['phone_number'] != null)
              Card(
                margin: EdgeInsets.zero,
                child: InkWell(
                  onTap: () async {
                    metrics.contact();
                    if (Platform.isAndroid) {
                      // Give time for request to finish before launch dialer
                      await Future.delayed(Duration(milliseconds: 300));
                    }
                    launch('tel:${authority['phone_number']}');
                  },
                  child: Padding(
                    padding: EdgeInsets.all(15),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(intl.get('status.exposure.contact.title'),
                                  style: subhead),
                              SizedBox(height: 5),
                              Text(intl.get('status.exposure.contact.body')),
                            ],
                          ),
                        ),
                        SizedBox(width: 5),
                        Material(
                          shape: CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          color: Theme.of(context).primaryColor,
                          child: Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(Icons.phone,
                                color: Colors.white, size: 25),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            /*
            * Remove test facility integration for the time being to get address
            * Flutter rendering issue.
            SizedBox(height: 20),
            Card(
              margin: EdgeInsets.zero,
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (ctx) => TestFacilities()),
                ),
                child: Padding(
                  padding: EdgeInsets.all(15),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          intl.get('status.exposure.testing.title'),
                          style: Theme.of(context)
                              .textTheme
                              .subtitle1
                              .merge(TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 5),
                        child: Image.asset('assets/clinic_medical_icon.png',
                            color: Theme.of(context).primaryColor, height: 30),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            */
            SizedBox(height: 10),
            ...faqs["exposure"].map((item) => InfoCard(item: item)),
            SizedBox(height: 10),
            aboutCard(),
            SizedBox(height: 20),
          ]),
        ),
      );
    });
  }
}

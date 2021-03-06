import 'dart:io';

import 'package:covidtrace/config.dart';
import 'package:covidtrace/intl.dart';
import 'package:covidtrace/privacy_policy.dart';
import 'package:covidtrace/helper/metrics.dart' as metrics;
import 'package:covidtrace/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:gact_plugin/gact_plugin.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'storage/user.dart';

class BlockButton extends StatelessWidget {
  final onPressed;
  final String label;

  BlockButton({this.onPressed, this.label});

  @override
  Widget build(BuildContext context) {
    var theme = Config.get()['theme']['onboarding'];

    return Row(children: [
      Expanded(
          child: RaisedButton(
              child: Text(label, style: TextStyle(fontSize: 20)),
              onPressed: onPressed,
              textColor: Color(int.parse(theme['button_text'])),
              color: Color(int.parse(theme['button_background'])),
              shape: StadiumBorder(),
              padding: EdgeInsets.all(15)))
    ]);
  }
}

class Onboarding extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => OnboardingState();
}

class OnboardingState extends State {
  var _pageController = PageController();
  var _requestExposure = false;
  var _requestNotification = false;

  // This is only reachable on Android
  void upgradeApi() {
    launch(Config.get()['support']['gps_link']);
  }

  void nextPage() => _pageController.nextPage(
      duration: Duration(milliseconds: 250), curve: Curves.easeOut);

  void requestPermission() async {
    AuthorizationStatus status;
    try {
      status = await GactPlugin.authorizationStatus;
      print('enable exposure notification $status');

      // Do not attempt to enable EN if status is unsupported
      if (status != AuthorizationStatus.Authorized &&
          status != AuthorizationStatus.Unsupported) {
        status = await GactPlugin.enableExposureNotification();
      }
    } catch (err) {
      print(err);
      var code = errorFromException(err);
      if (code == ErrorCode.notAuthorized || code == ErrorCode.unsupported) {
        status = AuthorizationStatus.NotAuthorized;
      }
    }

    setState(() {
      _requestExposure = status == AuthorizationStatus.Authorized;
    });

    nextPage();
  }

  void requestNotifications(bool selected) async {
    var plugin = FlutterLocalNotificationsPlugin();
    bool allowed = await plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        .requestPermissions(alert: true, sound: true);

    setState(() => _requestNotification = allowed);
    var user = await UserModel.find();
    await user.save();
  }

  void finish(AppState state) async {
    var user = state.user;
    user.onboarding = false;

    try {
      await state.saveUser(user);
      await state.checkStatus();
    } catch (err) {
      print(err);
    }

    metrics.onboard(
      authorized: _requestExposure,
      notifications: _requestNotification,
    );

    Navigator.of(context).pushReplacementNamed('/home');
  }

  void showPrivacyPolicy() {
    Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true, builder: (context) => PrivacyPolicy()));
  }

  @override
  Widget build(BuildContext context) {
    var intl = Intl.of(context);
    var config = Config.get()['onboarding'];
    var theme = Config.get()['theme']['onboarding'];
    var textColor = Color(int.parse(theme['text']));

    var themeData = ThemeData(
        textTheme: Theme.of(context).textTheme.apply(
              bodyColor: textColor,
              displayColor: textColor,
            ));

    var bodyText = themeData.textTheme.bodyText2
        .merge(TextStyle(fontSize: 16, height: 1.5));

    var deviceHeight = MediaQuery.of(context).size.height;
    var platform = Theme.of(context).platform;

    return Consumer<AppState>(builder: (context, state, _) {
      return AnnotatedRegion(
        value: theme['system_overlay'] == 'light'
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaleFactor: 1),
          child: Theme(
            data: themeData,
            child: Container(
              color: Color(int.parse(theme['background'])),
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: PageView(
                      controller: _pageController,
                      physics: NeverScrollableScrollPhysics(),
                      children: [
                        if (state.authStatus ==
                                AuthorizationStatus.Unsupported &&
                            Platform.isAndroid)
                          Stack(clipBehavior: Clip.antiAlias, children: [
                            SingleChildScrollView(
                                physics: AlwaysScrollableScrollPhysics(),
                                child: Column(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Center(
                                        child: Container(
                                          child: Image.asset(
                                            config['unsupported']['icon'],
                                            fit: BoxFit.contain,
                                            height: deviceHeight * .3,
                                          ),
                                        ),
                                      ),
                                      SizedBox(height: 10),
                                      Row(children: [
                                        Expanded(
                                            child: Text(
                                          intl.get(
                                              config['unsupported']['title']),
                                          style: themeData.textTheme.headline5,
                                        )),
                                      ]),
                                      SizedBox(height: 10),
                                      Text(
                                        intl.get(config['unsupported']['body']),
                                        style: bodyText,
                                      ),
                                    ])),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Column(children: [
                                BlockButton(
                                    onPressed: upgradeApi,
                                    label:
                                        intl.get(config['unsupported']['cta'])),
                                FlatButton(
                                  onPressed: nextPage,
                                  child: Text(
                                      intl.get(config['unsupported']['skip']),
                                      style: bodyText),
                                ),
                              ]),
                            ),
                          ]),
                        Stack(clipBehavior: Clip.antiAlias, children: [
                          SingleChildScrollView(
                              physics: AlwaysScrollableScrollPhysics(),
                              child: Column(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Center(
                                      child: Container(
                                        child: Image.asset(
                                          config['intro']['icon'],
                                          fit: BoxFit.contain,
                                          height: deviceHeight * .3,
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: 10),
                                    Row(children: [
                                      Expanded(
                                          child: Text(
                                        intl.get(config['intro']['title']),
                                        style: themeData.textTheme.headline5,
                                      )),
                                    ]),
                                    SizedBox(height: 10),
                                    Text(
                                      intl.get(config['intro']['body']),
                                      style: bodyText,
                                    ),
                                    SizedBox(height: 150),
                                  ])),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: BlockButton(
                                onPressed: nextPage,
                                label: intl.get(config['intro']['cta'])),
                          ),
                        ]),
                        Stack(
                          clipBehavior: Clip.antiAlias,
                          children: [
                            SingleChildScrollView(
                              physics: AlwaysScrollableScrollPhysics(),
                              child: Container(
                                child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Expanded(
                                            child: Text(
                                                intl.get(
                                                    config['privacy']['title']),
                                                style: themeData
                                                    .textTheme.headline5)),
                                        Container(
                                          child: Image.asset(
                                              config['privacy']['icon'],
                                              color: textColor,
                                              height: 40,
                                              fit: BoxFit.contain),
                                        ),
                                      ]),
                                      SizedBox(height: 10),
                                      Text(
                                        intl.get(config['privacy']['body']),
                                        style: bodyText,
                                      ),
                                      SizedBox(height: 10),
                                      ...config['privacy']['bullets'].map((b) {
                                        return Padding(
                                          padding: EdgeInsets.only(
                                              top: 10, bottom: 10),
                                          child: Row(children: [
                                            Image.asset(
                                              b['icon'],
                                              color: textColor,
                                              height: 25,
                                            ),
                                            SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                intl.get(b['title']),
                                                style: bodyText,
                                              ),
                                            ),
                                          ]),
                                        );
                                      }),
                                      SizedBox(height: 10),
                                      Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () => showPrivacyPolicy(),
                                          child: Text(
                                            intl.get(config['privacy']
                                                ['privacy_title']),
                                            style: bodyText.merge(TextStyle(
                                                decoration:
                                                    TextDecoration.underline)),
                                          ),
                                        ),
                                      ),
                                      SizedBox(height: 150),
                                    ]),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: BlockButton(
                                  onPressed: nextPage,
                                  label: intl.get(config['privacy']['cta'])),
                            ),
                          ],
                        ),
                        Stack(clipBehavior: Clip.antiAlias, children: [
                          SingleChildScrollView(
                              physics: AlwaysScrollableScrollPhysics(),
                              child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Expanded(
                                          child: Text(
                                              intl.get(config[
                                                      'exposure_notification']
                                                  ['title']),
                                              style: themeData
                                                  .textTheme.headline5)),
                                      Container(
                                        child: Image.asset(
                                            config['exposure_notification']
                                                ['icon'],
                                            color: textColor,
                                            height: 40,
                                            fit: BoxFit.contain),
                                      ),
                                    ]),
                                    SizedBox(height: 20),
                                    Text(
                                      intl.get(config['exposure_notification']
                                          ['body']),
                                      style: bodyText,
                                    ),
                                    SizedBox(height: 20),
                                    Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () => launch(intl.get(
                                            config['exposure_notification']
                                                ['learn_more_link'])),
                                        child: Text(
                                          intl.get(
                                              config['exposure_notification']
                                                  ['learn_more_title']),
                                          style: bodyText.merge(TextStyle(
                                              decoration:
                                                  TextDecoration.underline)),
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: 150),
                                  ])),
                          Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: BlockButton(
                                  label: intl.get(
                                      config['exposure_notification']['cta']),
                                  onPressed: () => requestPermission())),
                        ]),
                        Stack(clipBehavior: Clip.antiAlias, children: [
                          SingleChildScrollView(
                              physics: AlwaysScrollableScrollPhysics(),
                              child: Column(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      intl.get(config['notification_permission']
                                          ['title']),
                                      style: themeData.textTheme.headline5,
                                    ),
                                    SizedBox(height: 10),
                                    Text(
                                      intl.get(config['notification_permission']
                                          ['body']),
                                      style: bodyText,
                                    ),
                                    SizedBox(height: 20),
                                    Image.asset(platform == TargetPlatform.iOS
                                        ? config['notification_permission']
                                            ['preview_ios']
                                        : config['notification_permission']
                                            ['preview_android']),
                                    SizedBox(height: 20),
                                    if (platform == TargetPlatform.iOS)
                                      Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                              onTap: () => requestNotifications(
                                                  !_requestExposure),
                                              child: Row(children: [
                                                Expanded(
                                                    child: Text(
                                                        intl.get(config[
                                                                'notification_permission']
                                                            [
                                                            'enable_toggle_title']),
                                                        style: themeData
                                                            .textTheme
                                                            .headline6)),
                                                Switch.adaptive(
                                                    inactiveTrackColor:
                                                        Colors.black26,
                                                    activeColor: Color(
                                                        int.parse(theme[
                                                            'button_background'])),
                                                    value: _requestNotification,
                                                    onChanged:
                                                        requestNotifications),
                                              ]))),
                                    SizedBox(height: 150),
                                  ])),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: BlockButton(
                                onPressed: () => finish(state),
                                label: intl.get(
                                    config['notification_permission']['cta'])),
                          ),
                        ]),
                      ]),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

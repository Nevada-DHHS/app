import 'package:covidtrace/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

class PrivacyPolicy extends StatefulWidget {
  @override
  PrivacyPolicyState createState() => PrivacyPolicyState();
}

class PrivacyPolicyState extends State<PrivacyPolicy> {
  String _file;

  void loadPolicy() async {
    String privacyLink = Intl.of(context).get('privacy_policy.content');

    var file = await rootBundle.loadString(privacyLink);
    setState(() {
      _file = file;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_file == null) {
      loadPolicy();
    }

    return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(Intl.of(context).get('privacy_policy.title')),
        ),
        body: _file != null
            ? Markdown(
                data: _file,
                selectable: false,
                onTapLink: (url) => launch(url),
              )
            : Container());
  }
}

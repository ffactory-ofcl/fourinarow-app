import 'package:flutter/material.dart';
import 'package:four_in_a_row/inherit/user.dart';
import 'package:four_in_a_row/menu/common/menu_common.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: FiarAppBar(
        title: "Friend Requests",
        threeDots: [
          FiarThreeDotItem(
            'Feedback',
            onTap: () {
              showFeedbackDialog(context);
            },
          ),
        ],
      ),
      body: ListView(
        children: [
          Consumer<UserInfo>(
            builder: (_, userInfo, __) => ListTile(
              leading: Icon(Icons.person_outline_rounded),
              title: Text('Account'),
              subtitle:
                  userInfo.loggedIn ? Text(userInfo.user!.username) : null,
              enabled: userInfo.loggedIn,
            ),
          ),
        ],
      ),
    );
  }
}

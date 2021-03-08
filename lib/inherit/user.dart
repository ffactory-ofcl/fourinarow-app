import 'dart:convert';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:four_in_a_row/util/fiar_shared_prefs.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:four_in_a_row/util/constants.dart' as constants;

import 'package:four_in_a_row/util/extensions.dart';

class UserInfo with ChangeNotifier {
  http.Client _client = http.Client();

  // bool _ok = false;
  bool refreshing = false;
  bool offline = false;
  // bool loadedInfo = false;

  String? username;
  String? password;

  User? user;

  bool get loggedIn => username != null && password != null && user != null;

  UserInfo() {
    loadCredentials();
  }

  Map<String, String> _body(String username, String password) {
    return {
      "username": username,
      "password": password,
    };
  }

  void logOut() async {
    // this._ok = false;
    this.username = null;
    this.password = null;
    this.user = null;

    FiarSharedPrefs.remove('username');
    FiarSharedPrefs.remove('password');
  }

  void loadCredentials() async {
    this.setCredentials(
        FiarSharedPrefs.accountUsername, FiarSharedPrefs.accountPassword);
  }

  void setCredentials(String username, String password) async {
    FiarSharedPrefs.accountUsername = username;
    FiarSharedPrefs.accountPassword = password;

    this.username = username;
    this.password = password;
    _loadInfo();
  }

  Future<bool> addFriend(String id, [VoidCallback? callback]) async {
    var u = this.username;
    var pw = this.password;
    if (u == null || pw == null) {
      return false;
    }

    var response = await _client.post(
        "${constants.HTTP_URL}/api/users/me/friends?id=$id",
        body: _body(u, pw));
    if (response.statusCode == 200) {
      if (callback != null) {
        callback();
      }
      await _loadInfo();
      // _friends.firstWhere((u) => u.id == id)?.isFriend = true;
      return true;
    } else {
      _loadInfo();
      return false;
    }
  }

  Future<UserInfo?> _loadInfo({
    delay = false,
    shouldSetState = false,
  }) async {
    if (shouldSetState == true) {
      refreshing = true;
    }

    if (username == null) return null;
    if (password == null) return null;
    // rebuild();

    var req =
        http.Request("GET", Uri.parse('${constants.HTTP_URL}/api/users/me'))
          ..headers['Authorization'] = "Basic " +
              base64.encode(Utf8Codec().encode(username! + ":" + password!));
    // ..bodyFields = _body;

    try {
      var response = await _client.send(req).timeout(Duration(seconds: 4));
      if (response.statusCode == 200) {
        User? user =
            User.fromMap(jsonDecode(await response.stream.bytesToString()));

        this.user = user;
      }
      offline = false;
    } on SocketException catch (e) {
      if (e.osError?.errorCode == 7) {
        offline = true;
      }
    } on http.ClientException {
      offline = true;
    }

    refreshing = false;
    if (this.loggedIn && delay) {
      await Future.delayed(Duration(milliseconds: 300));
    }
    // print("set state in userinfo refresh");
    notifyListeners();
    // print("reloaded user info");
    return Future.value(this);

    // .catchError(() {});
  }

  Future<UserInfo?> refresh({shouldSetState: true}) {
    return _loadInfo(delay: true, shouldSetState: shouldSetState);
  }

  Future<PublicUser?> getUserInfo({required String userId}) async {
    try {
      var resp = await _client.get("${constants.HTTP_URL}/api/users/$userId");
      if (resp.statusCode == 200) {
        return PublicUser.fromMap(jsonDecode(resp.body));
      } else {
        throw HttpException("Not found");
      }
    } on Exception {
      print("Error trying to get user info");
      return null;
    }
  }
}

class GameInfo extends Equatable {
  final int skillRating;
  final int playerRank;

  GameInfo(this.skillRating, this.playerRank);

  static GameInfo? fromMap(Map<String, dynamic> map) {
    for (String key in ['skill_rating']) {
      if (!map.containsKey(key)) return null;
    }

    return GameInfo(
      map['skill_rating'] as int,
      255,
    );
  }

  @override
  List<Object> get props => [skillRating, playerRank];
}

enum FriendState { IsFriend, IsRequestedByMe, HasRequestedMe, None, Loading }

extension FriendStateExtension on FriendState {
  Widget icon() {
    switch (this) {
      case FriendState.IsFriend:
        return Icon(Icons.check);
      case FriendState.IsRequestedByMe:
        return Icon(Icons.outgoing_mail);
      case FriendState.HasRequestedMe:
        return Icon(Icons.move_to_inbox_rounded);
      case FriendState.None:
        return Icon(Icons.person_add);
      case FriendState.Loading:
        return Container(
            width: 24, height: 24, child: CircularProgressIndicator());
    }
  }
}

class PublicUser {
  final String id;
  final String name;
  final GameInfo gameInfo;
  FriendState friendState;
  bool isPlaying;

  PublicUser(
    this.id,
    this.name,
    this.gameInfo, {
    this.friendState = FriendState.None,
    this.isPlaying = false,
  });

  static PublicUser? fromMap(Map<String, dynamic> map) {
    for (String key in ['username', 'game_info', 'id']) {
      if (!map.containsKey(key)) return null;
    }
    GameInfo? gameInfo = GameInfo.fromMap(map['game_info']);
    if (gameInfo == null) return null;

    return PublicUser(
      map['id'],
      map['username'],
      gameInfo,
      isPlaying: map['playing'] ?? false,
    );
  }
}

class User extends Equatable {
  User({
    required this.id,
    required this.username,
    // this.password,
    required this.email,
    required this.friends,
    required this.friendRequests,
    required this.gameInfo,
  });

  final String id;
  final String username;
  // final String password;
  final String email;
  final List<PublicUser> friends;
  final List<FriendRequest> friendRequests;
  final GameInfo gameInfo;

  static User? fromMap(Map<String, dynamic> map) {
    for (String key in ['id', 'username', 'game_info', 'friends', 'email']) {
      if (!map.containsKey(key)) return null;
    }
    List<PublicUser> friends = (map['friends'] as List<dynamic>)
        .map((dynamic friendMap) =>
            PublicUser.fromMap(friendMap as Map<String, dynamic>))
        .toList()
        .filterNotNull();

    List<FriendRequest> friendRequests =
        (map['friend_requests'] as List<dynamic>)
            .map((dynamic friendMap) =>
                FriendRequest.fromMap(friendMap as Map<String, dynamic>))
            .toList()
            .filterNotNull();

    GameInfo? gameInfo = GameInfo.fromMap(map['game_info']);
    if (gameInfo == null) return null;

    return User(
      id: map['id'] as String,
      username: map['username'] as String,
      email: map['email'] as String,
      friends: friends,
      friendRequests: friendRequests,
      gameInfo: gameInfo,
    );
  }

  @override
  List<Object> get props =>
      [id, username, email, friends, friendRequests, gameInfo];
}

enum FriendRequestDirection { Incoming, Outgoing }

extension FriendRequestDirectionExtension on FriendRequestDirection {
  static FriendRequestDirection? fromString(String s) {
    if (s == "Incoming")
      return FriendRequestDirection.Incoming;
    else if (s == "Outgoing")
      return FriendRequestDirection.Outgoing;
    else
      return null;
  }
}

class FriendRequest {
  final FriendRequestDirection direction;
  final PublicUser other;

  FriendRequest({required this.direction, required this.other});

  static FriendRequest? fromMap(Map<String, dynamic> map) {
    for (String key in ['direction', 'other']) {
      if (!map.containsKey(key)) return null;
    }
    FriendRequestDirection? direction =
        FriendRequestDirectionExtension.fromString(map['direction']);
    if (direction == null) return null;

    PublicUser? other = PublicUser.fromMap(map['other']);
    if (other == null) return null;

    return FriendRequest(
      direction: direction,
      other: other,
    );
  }
}

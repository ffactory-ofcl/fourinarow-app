import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:four_in_a_row/util/constants.dart' as constants;

import '../messages.dart';
import 'all.dart';

class Error extends GameState {
  final GameStateError error;

  Error(this.error, Sink<PlayerMessage> sink) : super(sink);

  createState() => ErrorState();

  @override
  GameState handleMessage(ServerMessage msg) {
    return super.handleMessage(msg);
  }

  GameState handlePlayerMessage(PlayerMessage msg) {
    return null;
  }
}

class ErrorState extends State<Error> {
  @override
  void initState() {
    super.initState();
    http.post(
      "${constants.URL}/api/crashreport",
      body: widget.error.runtimeType.toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              "Error! :(",
              style: TextStyle(
                fontSize: 32,
              ),
            ),
            SizedBox(height: 12),
            // SizedBox(height: 6),
            Text((widget.error != null ? "${widget.error.toString()}\n" : "") +
                'Please try again' +
                (widget.error.isUserCaused
                    ? ''
                    : ' in a moment\nDon\'t worry, a bug report\nhas been sent.')),
          ],
        ),
      ),
    );
  }
}

abstract class GameStateError {
  GameStateError(this.isUserCaused);
  final bool isUserCaused;
}

class Internal extends GameStateError {
  // final String message;
  Internal(bool isUserCaused) : super(isUserCaused);

  @override
  String toString() {
    return "The server encountered an unexpeced internal error.";
  }
}

class LobbyNotFound extends GameStateError {
  LobbyNotFound() : super(true);

  @override
  String toString() {
    return "The lobby code you entered does not exist.";
  }
}

class AlreadyPlaying extends GameStateError {
  AlreadyPlaying() : super(true);

  @override
  String toString() {
    return "Another device is currently playing with this account.";
  }
}

class LobbyClosed extends GameStateError {
  LobbyClosed() : super(false);

  @override
  String toString() {
    return "The lobby has been closed.";
  }
}

class NoConnection extends GameStateError {
  NoConnection() : super(true);

  @override
  String toString() {
    return "Could not connect, please check your internet.";
  }
}

class Timeout extends GameStateError {
  Timeout() : super(false);

  @override
  String toString() {
    return "Connection timed out! Couldn't reach the server.";
  }
}

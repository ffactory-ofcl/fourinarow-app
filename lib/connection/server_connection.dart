import 'dart:async';
import 'dart:math';
// ignore: import_of_legacy_library_into_null_safe
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:flutter/material.dart';
import 'package:four_in_a_row/util/constants.dart';
import 'messages.dart';

class ServerConnection with ChangeNotifier {
  WebSocketChannel? _connection;

  StreamController<ServerMessage> _serverMsgStreamCtrl =
      StreamController<ServerMessage>.broadcast();
  Stream<ServerMessage> get serverMsgStream => _serverMsgStreamCtrl.stream;
  // StreamSubscription? _serverMsgSub;

  StreamController<PlayerMessage> _playerMsgStreamCtrl =
      StreamController<PlayerMessage>.broadcast();
  Stream<PlayerMessage> get playerMsgStream => _playerMsgStreamCtrl.stream;
  StreamSubscription? _playerMsgSub;

  StreamController<ReliablePacketOut> _reliablePktOutStreamCtrl =
      StreamController<ReliablePacketOut>.broadcast();
  StreamSubscription? _reliablePktOutSub;

  StreamController<ReliablePacketIn> _wsInStreamCtrl =
      StreamController<ReliablePacketIn>.broadcast();
  StreamSubscription? _wsInSub;

  int _serverMsgIndex = 0;
  final List<QueuedMessage<ServerMessage>> _serverMsgQ = [];
  int _playerMsgIndex = 0;
  final List<QueuedMessage<PlayerMessage>> _playerMsgQ = [];

  SessionState _sessionState = SessionStateIdle();

  bool get connected => _sessionState is SessionStateConnected;

  int _connectionTries = 0;

  ServerConnection() {
    _connect();
    _resendQueuedInterval();
  }

  void send(PlayerMessage msg) {
    this._playerMsgStreamCtrl.add(msg);
  }

  void retryConnection({bool force = false}) {
    if (this._sessionState is! SessionStateConnected || force) {
      _connect();
    }
  }

  void close() {
    _serverMsgStreamCtrl.close();
    _playerMsgStreamCtrl.close();

    _wsInStreamCtrl.close();
    _reliablePktOutStreamCtrl.close();
  }

  void _connect() {
    this._connectionTries += 1;
    print(">> #TRY# to connect (${this._connectionTries})");
    // this._serverMsgSub?.cancel();
    this._playerMsgSub?.cancel();

    this._wsInSub?.cancel();
    this._reliablePktOutSub?.cancel();

    if (!kIsWeb) {
      this._connection = IOWebSocketChannel.connect(Uri.parse(WS_URL),
          pingInterval: Duration(seconds: 1));
    } else {
      throw UnimplementedError();
    }
    // .connect(
    //   ,
    // );
    _wsInSub = _handleWsIn(_connection!.stream);
    _reliablePktOutSub = _handleReliablePktOut(_connection!.sink);

    // _serverMsgSub = _handleServerMsg();
    _playerMsgSub = _handlePlayerMsg();

    var sessionState = this._sessionState;
    if (sessionState is SessionStateDisconnected) {
      _reliablePktOutStreamCtrl
          .add(ReliablePktReconnect(sessionState.identifier));
      this._sessionState =
          SessionStateWaiting(identifier: sessionState.identifier);
    } else if (sessionState is SessionStateWaiting &&
        sessionState.identifier != null) {
      _reliablePktOutStreamCtrl
          .add(ReliablePktReconnect(sessionState.identifier!));
      this._sessionState =
          SessionStateWaiting(identifier: sessionState.identifier!);
    } else if (sessionState is! SessionStateConnected) {
      _reliablePktOutStreamCtrl.add(ReliablePktReqNew());
      this._sessionState = SessionStateWaiting();
    }

    notifyListeners();
  }

  StreamSubscription _handleWsIn(Stream<dynamic> wsStream) {
    return wsStream.listen(this._receivedWsMsg,
        onError: this._websocketErr, onDone: this._websocketDone);
  }

  StreamSubscription _handleReliablePktOut(WebSocketSink wsSink) {
    return this._reliablePktOutStreamCtrl.stream.listen((rPkt) {
      if (rPkt is ReliablePktMsgOut) {
        this._playerMsgQ.add(QueuedMessage(rPkt.id, rPkt.msg));
      }

      String msgStr = rPkt.serialize();
      print("<< $msgStr");
      wsSink.add(msgStr);
    });
  }

  StreamSubscription _handlePlayerMsg() {
    return this._playerMsgStreamCtrl.stream.listen((msg) {
      this._playerMsgIndex += 1;
      this
          ._reliablePktOutStreamCtrl
          .add(ReliablePktMsgOut(this._playerMsgIndex, msg));
    });
  }

  void _receivedWsMsg(dynamic msg) {
    if (msg is String) {
      print(">> $msg");
      var rPkt = ReliablePacketIn.parse(msg);
      if (rPkt == null) return;
      this._receivedReliablePacket(rPkt);
    } else {
      print(">> #OTR# \"$msg\"");
    }
  }

  void _websocketErr(dynamic? err) {
    print(">> #ERR# \"${err.toString()}\"");
  }

  void _websocketDone() {
    print(
        ">> #DONE# Reason: ${_connection?.closeCode} - ${_connection?.closeReason}");
    var _sessionState = this._sessionState;
    if (_sessionState is SessionStateConnected) {
      this._sessionState = SessionStateDisconnected(_sessionState.identifier);
    }
    notifyListeners();
    Future.delayed(
        Duration(milliseconds: 500 * max(_connectionTries, 8)), _connect);
  }

  void _resetReliabilityLayer() {
    this._playerMsgQ.removeRange(0, this._playerMsgQ.length);
    this._serverMsgQ.removeRange(0, this._serverMsgQ.length);
    this._playerMsgIndex = 0;
    this._serverMsgIndex = 0;
  }

  void _receivedReliablePacket(ReliablePacketIn rPkt) {
    if (rPkt is ReliablePktAckIn) {
      if (this._playerMsgQ.any((msg) => msg.id == rPkt.id)) {
        this._playerMsgQ.removeWhere((msg) => msg.id == rPkt.id);
      } else {
        this._resetReliabilityLayer();
        this.retryConnection(force: true);
      }
    } else if (rPkt is ReliablePktMsgIn) {
      final int expectedId = this._serverMsgIndex + 1;
      if (rPkt.id == expectedId) {
        this._serverMsgIndex = rPkt.id;
        this._serverMsgStreamCtrl.sink.add(rPkt.msg);
        this._ackMessage(rPkt.id);
      } else if (rPkt.id > expectedId) {
        this._queueMessgage(rPkt.id, rPkt.msg);
        this._ackMessage(this._serverMsgIndex);
      } else {
        // Client re-sent already known message -> maybe ack got lost -> ack but don't process
        this._ackMessage(rPkt.id);
      }
      this._processQueue();
    } else if (this._sessionState is SessionStateWaiting &&
        rPkt is ReliablePktNotFound) {
      this._serverMsgStreamCtrl.add(MsgReset());
      this._reliablePktOutStreamCtrl.add(ReliablePktReqNew());
      this._sessionState = SessionStateWaiting();
    } else if (rPkt is ReliablePktFound) {
      _connectionTries = 0;
      var sessionState = this._sessionState;
      if (sessionState is SessionStateWaiting && sessionState.isNew) {
        this._resetReliabilityLayer();
      }
      this._sessionState = SessionStateConnected(rPkt.id);
      notifyListeners();
    } else {
      throw UnimplementedError("Unexpected Reliable Pkt $rPkt");
    }
  }

  void _ackMessage(int id) {
    this._reliablePktOutStreamCtrl.add(ReliablePktAckOut(id));
  }

  void _queueMessgage(int id, ServerMessage msg) {
    this._serverMsgQ.add(QueuedMessage(id, msg));
  }

  void _processQueue() {
    bool added = false;
    do {
      [...this._serverMsgQ].asMap().forEach((index, queuedMessage) {
        int expectedId = this._serverMsgIndex + 1;
        if (queuedMessage.id == expectedId) {
          this._serverMsgQ.removeAt(index);
          this._serverMsgIndex = expectedId;
          this._serverMsgStreamCtrl.sink.add(queuedMessage.msg);
          this._ackMessage(expectedId);
          added = true;
        }
      });
    } while (added);
  }

  void _resendQueuedInterval() {
    Timer.periodic(Duration(milliseconds: QUEUE_CHECK_INTERVAL_MS),
        (_) => _resendQueued());
  }

  void _resendQueued() {
    DateTime threshold = DateTime.now()
        .subtract(Duration(milliseconds: QUEUE_RESEND_TIMEOUT_MS));
    [...this._playerMsgQ].asMap().entries.forEach((MapEntry entry) {
      int index = entry.key;
      QueuedMessage<PlayerMessage> queuedMessage = entry.value;

      if (queuedMessage.sent.isBefore(threshold)) {
        this
            ._reliablePktOutStreamCtrl
            .add(ReliablePktMsgOut(queuedMessage.id, queuedMessage.msg));
        this._playerMsgQ.removeAt(index);
      }
    });
  }
}

abstract class SessionState {}

class SessionStateIdle extends SessionState {}

class SessionStateWaiting extends SessionState {
  final String? identifier;

  bool get isNew => identifier == null;

  SessionStateWaiting({this.identifier});
}

class SessionStateConnected extends SessionState {
  final String identifier;

  SessionStateConnected(this.identifier);
}

class SessionStateDisconnected extends SessionState {
  final String identifier;

  SessionStateDisconnected(this.identifier);
}

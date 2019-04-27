import 'dart:async';
import 'dart:convert';

import 'package:attendance/backend/attend_model.dart';
import 'package:attendance/backend/session.dart';
import 'package:attendance/homePage/home_page.dart';
import 'package:attendance/scan_exceptions.dart';
import 'package:barcode_scan/barcode_scan.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

///Business logic
abstract class HomePageViewModel extends State<HomePage> {
  ///Construct Home page Viewmodel
  HomePageViewModel() {
    auth.currentUser().then((FirebaseUser user) {
      _mUser = user;
      setState(() {
        if (_mUser.email != null) {
          mail = _mUser.email;
        }
        if (_mUser.displayName != null) {
          name = _mUser.displayName;
        }
        if (_mUser.photoUrl != null) {
          imageUrl = _mUser.photoUrl;
        }
        _fillData();
      });
    });
  }

  ///scan message
  String scanResult = "Scan Error: Make sure you're scanning the right code";

  ///l items
  List<AttendModel> litems = <AttendModel>[];

  ///u items
  List<AttendModel> uitems = <AttendModel>[];

  ///FB Auth object
  final FirebaseAuth auth = FirebaseAuth.instance;

  FirebaseUser _mUser;

  ///User mail address
  String mail = '';

  ///User image url
  String imageUrl = '';

  ///User fullname
  String name = '';

  ///perform sign out
  void signOut() {
    auth.signOut();
    Navigator.of(context).pushReplacementNamed('/login');
  }

  ///open details
  Future<void> openDetails(AttendModel model) async {
    AttendModel.selected = model;
    await Navigator.of(context).pushNamed('/details');
    await _fillData();
  }

  /// perform scan
  Future<void> scan() async {
    try {
      final String barcode = await BarcodeScanner.scan();
      final String uid = _mUser.uid;
      final Session session = Session.fromMap(json.decode(barcode));
      // @todo #9 save locally and call api /newsession instead of using firebase database
      final DatabaseReference sessionRef = FirebaseDatabase.instance
          .reference()
          .child(session.adminUID)
          .child('classes')
          .child(session.classKey)
          .child('sessions')
          .child(session.key);
      if (await _isScanned(sessionRef, _mUser)) {
        throw AlreadyScannedSessionException(
            'already scanned atendance to this session');
      }
      final DatabaseReference attendanceRef =
      FirebaseDatabase.instance.reference().child('attendances').push();
      final DateTime now = DateTime.now();
      final Map<String, dynamic> map = <String, dynamic>{};
      map['session'] = session.key;
      map['sessionClass'] = session.classKey;
      map['sessionAdmin'] = session.adminUID;
      map['user'] = uid;
      map['arriveTime'] = now.toIso8601String();
      map['leaveTime'] = 'NULL';
      await attendanceRef.set(map);
      await sessionRef.child('attended').push().set(attendanceRef.key);
      await FirebaseDatabase.instance
          .reference()
          .child(uid)
          .child('attended')
          .push()
          .set(attendanceRef.key);
      setState(() {
        scanResult = 'scanned successfully';
      });
    } on PlatformException catch (e) {
      if (e.code == BarcodeScanner.CameraAccessDenied) {
        setState(() {
          scanResult = 'You did not grant the camera permission!';
        });
      } else {
        setState(() => scanResult = 'Unknown error: $e');
      }
    } on FormatException {
      setState(() => print('Scan Cancelled'));
    } on AlreadyScannedSessionException catch (e) {
      setState(() {
        scanResult = e.cause;
      });
    } on Exception catch (e) {
      setState(() => print('Unknown error: $e'));
    }
  }

  // @todo #9 delete this (checking will be performed in the backend)
  Future<bool> _isScanned(DatabaseReference session, FirebaseUser user) async {
    final DataSnapshot attendees = await session.child('attended').once();
    final Map<dynamic, dynamic> value = attendees.value;
    if (value == null || value.isEmpty) {
      return false;
    }
    for (String key in value.keys) {
      final DataSnapshot ref = await FirebaseDatabase.instance
          .reference()
          .child('attendances')
          .child(value[key])
          .once();
      if (ref.value['user'] == user.uid) {
        debugPrint(user.uid);
        debugPrint(ref.value['user']);
        return true;
      }
    }
    return false;
  }

  // @todo #9 get data from api /getInfo and save in user class (add more endpoints if needed)
  Future<void> _fillData() async {
    litems.clear();
    uitems.clear();
    FirebaseDatabase.instance
        .reference()
        .child(_mUser.uid)
        .child('attended')
        .onChildAdded
        .listen((Event event) async {
      final String key = event.snapshot.value;
      final DatabaseReference itemRef =
      FirebaseDatabase.instance.reference().child('attendances').child(key);
      final DataSnapshot item = await itemRef.once();
      final DatabaseReference classRef = FirebaseDatabase.instance
          .reference()
          .child(item.value['sessionAdmin'])
          .child('classes')
          .child(item.value['sessionClass']);
      final DataSnapshot classSnap = await classRef.once();
      final String name = classSnap.value['name'];
      final DataSnapshot sessionSnap =
      await classRef.child('sessions').child(item.value['session']).once();
      final String date = json.decode(sessionSnap.value['qrval'])['date'];
      final String attendTime = item.value['arriveTime'];
      final String leaveTime = item.value['leaveTime'];
      setState(() {
        AttendModel m;
        m = AttendModel(key, name, date, attendTime, leaveTime);
        if (m.leaveDate == 'NULL') {
          uitems.add(m);
        } else {
          litems.add(m);
        }
      });
    });
  }
}

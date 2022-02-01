//step 1: collecting our local ice candidates
//step 2: send it to our room
//step 3: listen to remote session descrption
//step 4: listen for remote ice candidate
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:fimi/services/DatabaseServices/databaseServices.dart';
import 'package:fimi/sharedPreferences/sharePreferences.dart';


typedef void StreamStateCallback(MediaStream stream);
class Signaling{

  Map<String, dynamic> configuration = {
    'iceServers': [
      {
        'urls': [
          'stun:stun1.l.google.com:19302',
          'stun:stun2.l.google.com:19302'
        ]
      }
    ]
  };

  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  MediaStream? remoteStream;
  String? roomId;
  String? currentRoomText;
  StreamStateCallback? onAddRemoteStream;

  Future<String> createRoom(RTCVideoRenderer remoteRenderer) async {
    FirebaseFirestore db = FirebaseFirestore.instance;
    DocumentReference roomRef = db.collection('rooms').doc("abcd");

    print('Create PeerConnection with configuration: $configuration');

    peerConnection = await createPeerConnection(configuration);

    registerPeerConnectionListeners();

    localStream?.getTracks().forEach((track) {
      peerConnection?.addTrack(track, localStream!);
    });

    // Code for collecting ICE candidates below
    var callerCandidatesCollection = roomRef.collection('callerCandidates');

    peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      print('Got candidate: ${candidate.toMap()}');
      callerCandidatesCollection.add(candidate.toMap());
    };
    // Finish Code for collecting ICE candidate

    // Add code for creating a room
    RTCSessionDescription offer = await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);
    print('Created offer: $offer');

    Map<String, dynamic> roomWithOffer = {'offer': offer.toMap()};

    await roomRef.set(roomWithOffer);
    var roomId = roomRef.id;
    print('New room created with SDK offer. Room ID: $roomId');
    currentRoomText = 'Current room is $roomId - You are the caller!';
    // Created a Room

    peerConnection?.onTrack = (RTCTrackEvent event) {
      print('Got remote track: ${event.streams[0]}');

      event.streams[0].getTracks().forEach((track) {
        print('Add a track to the remoteStream $track');
        remoteStream?.addTrack(track);
      });
    };

    // Listening for remote session description below
    roomRef.snapshots().listen((snapshot) async {
      print('Got updated room: ${snapshot.data()}');

      Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;
      if (peerConnection?.getRemoteDescription() != null &&
          data['answer'] != null) {
        var answer = RTCSessionDescription(
          data['answer']['sdp'],
          data['answer']['type'],
        );

        print("Someone tried to connect");
        await peerConnection?.setRemoteDescription(answer);
      }
    });
    // Listening for remote session description above

    // Listen for remote Ice candidates below
    roomRef.collection('calleeCandidates').snapshots().listen((snapshot) {
      snapshot.docChanges.forEach((change) {
        if (change.type == DocumentChangeType.added) {
          Map<String, dynamic> data = change.doc.data() as Map<String, dynamic>;
          // print('Got new remote ICE candidate: ${jsonEncode(data)}');
          peerConnection!.addCandidate(
            RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            ),
          );
        }
      });
    });
    // Listen for remote ICE candidates above

    return roomId;
  }

  Future<void> joinRoom(String roomId, RTCVideoRenderer remoteVideo) async {
    FirebaseFirestore db = FirebaseFirestore.instance;
    DocumentReference roomRef = db.collection('rooms').doc('$roomId');
    var roomSnapshot = await roomRef.get();
    print('Got room ${roomSnapshot.exists}');

    if (roomSnapshot.exists) {
      print('Create PeerConnection with configuration: $configuration');
      peerConnection = await createPeerConnection(configuration);

      registerPeerConnectionListeners();

      localStream?.getTracks().forEach((track) {
        peerConnection?.addTrack(track, localStream!);
      });

      // Code for collecting ICE candidates below
      var calleeCandidatesCollection = roomRef.collection('calleeCandidates');
      peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate == null) {
          print('onIceCandidate: complete!');
          return;
        }
        print('onIceCandidate: ${candidate.toMap()}');
        calleeCandidatesCollection.add(candidate.toMap());
      };
      // Code for collecting ICE candidate above

      peerConnection?.onTrack = (RTCTrackEvent event) {
        print('Got remote track: ${event.streams[0]}');
        event.streams[0].getTracks().forEach((track) {
          print('Add a track to the remoteStream: $track');
          remoteStream?.addTrack(track);
        });
      };

      // Code for creating SDP answer below
      var data = roomSnapshot.data() as Map<String, dynamic>;
      print('Got offer $data');
      var offer = data['offer'];
      await peerConnection?.setRemoteDescription(
        RTCSessionDescription(offer['sdp'], offer['type']),
      );
      var answer = await peerConnection!.createAnswer();
      print('Created Answer $answer');

      await peerConnection!.setLocalDescription(answer);

      Map<String, dynamic> roomWithAnswer = {
        'answer': {'type': answer.type, 'sdp': answer.sdp}
      };

      await roomRef.update(roomWithAnswer);
      // Finished creating SDP answer

      // Listening for remote ICE candidates below
      roomRef.collection('callerCandidates').snapshots().listen((snapshot) {
        snapshot.docChanges.forEach((document) {
          var data = document.doc.data() as Map<String, dynamic>;
          print(data);
          print('Got new remote ICE candidate: $data');
          peerConnection!.addCandidate(
            RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            ),
          );
        });
      });
    }
  }

  Future<void> openUserMedia(
      RTCVideoRenderer localVideo,
      RTCVideoRenderer remoteVideo,
      ) async {
    var stream = await navigator.mediaDevices
        .getUserMedia({'video': true, 'audio': false});
    

      localVideo.srcObject = stream;
      localStream = stream;


    remoteVideo.srcObject = await createLocalMediaStream('key');
  }

  Future<void> hangUp(RTCVideoRenderer localVideo) async {
    List<MediaStreamTrack> tracks = localVideo.srcObject!.getTracks();
    tracks.forEach((track) {
      track.stop();
    });

    if (remoteStream != null) {
      remoteStream!.getTracks().forEach((track) => track.stop());
    }
    if (peerConnection != null) peerConnection!.close();

    if (roomId != null) {
      var db = FirebaseFirestore.instance;
      var roomRef = db.collection('rooms').doc(roomId);
      var calleeCandidates = await roomRef.collection('calleeCandidates').get();
      calleeCandidates.docs.forEach((document) => document.reference.delete());

      var callerCandidates = await roomRef.collection('callerCandidates').get();
      callerCandidates.docs.forEach((document) => document.reference.delete());

      await roomRef.delete();
    }

    localStream!.dispose();
    remoteStream?.dispose();
  }

  void registerPeerConnectionListeners() {
    peerConnection?.onIceGatheringState = (RTCIceGatheringState state) {
      print('ICE gathering state changed: $state');
    };

    peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
      print('Connection state change: $state');
    };

    peerConnection?.onSignalingState = (RTCSignalingState state) {
      print('Signaling state change: $state');
    };

    peerConnection?.onIceGatheringState = (RTCIceGatheringState state) {
      print('ICE connection state change: $state');
    };

    peerConnection?.onAddStream = (MediaStream stream) {
      print("Add remote stream");
      onAddRemoteStream?.call(stream);
      remoteStream = stream;
    };
  }

  // RTCPeerConnection? peerConnection ;
  // MediaStream? localStream;
  // MediaStream? remoteStream;
  // StreamStateCallback? onAddRemoteStream;
  // DatabaseServices databaseServices = new DatabaseServices();
  //
  //
  // Map<String, dynamic> configuration = {
  //     "iceServers": [
  //       {
  //         "urls": [
  //           "stun:stun.l.google.com:19302",
  //         ]
  //       }
  //     ]
  //   };
  //
  //
  // createConnection(String? roomId) async{
  //
  //
  //   final Map<String, dynamic> offerSdpConstraints = {
  //     "mandatory": {
  //       "OfferToReceiveAudio": true,
  //       "OfferToReceiveVideo": true,
  //     },
  //     "Optional": []
  //   };
  //
  //    peerConnection = await createPeerConnection(configuration,offerSdpConstraints);
  //   registerPeerConnectionListeners();
  //
  //        peerConnection!.onIceConnectionState = (e) {
  //     print('connectionState:'+ e.toString());
  //   };
  //
  //   localStream?.getTracks().forEach((track) {
  //     print('track Added');
  //     peerConnection?.addTrack(track);
  //
  //
  //   });
  //
  //    peerConnection?.onIceConnectionState = (e) {
  //     print(e);
  //   };
  //
  //   String? userName = await SharedPreferencesHelper.getUserNameSharedPrefrences();
  //
  // databaseServices.setCaller(roomId!, userName!);
  //
  //   peerConnection?.onIceCandidate = (RTCIceCandidate candidate){
  //     databaseServices.addCallerCandidates(candidate.toMap(), roomId!);
  //   };
  //
  //   RTCSessionDescription offer = await peerConnection!.createOffer();
  //
  //   await peerConnection!.setLocalDescription(offer);
  //
  //   databaseServices.addOfferOrAnswerSdp({"offer":offer.toMap()}, roomId!);
  //
  //   DocumentReference sdpCollectionRef = await  databaseServices.getSdpRoomRef(roomId);
  //
  //   sdpCollectionRef.snapshots().listen((snapshot) async {
  //    print('Got updated room: ${snapshot.data()}');
  //
  //     Map<String ,dynamic> data = snapshot.data() as Map<String , dynamic>;
  //     print('data------'+data['answer']['sdp']);
  //     if(peerConnection!.getRemoteDescription() != null && data['answer'] != null ){
  //         var answer = RTCSessionDescription(data['answer']['sdp'], data['answer']['type']);
  //
  //         await peerConnection?.setRemoteDescription(answer);
  //
  //         var answer2 = await peerConnection?.getRemoteDescription();
  //
  //         print("answer 2 : $answer2");
  //     }
  //   });
  //
  //   peerConnection?.onTrack = (RTCTrackEvent event) {
  //       print('Got remote track: ${event.streams[0]}');
  //       event.streams[0].getTracks().forEach((track) {
  //         print('Add a track to the remoteStream: $track');
  //         remoteStream?.addTrack(track);
  //       });
  //     };
  //
  //   CollectionReference calleeCandidateCollectionRef = await databaseServices.newCalleeCandidateCheck(roomId);
  //
  //   calleeCandidateCollectionRef.snapshots().listen((snapshot) {
  //     snapshot.docChanges.forEach((change) {
  //       if(change.type == DocumentChangeType.added){
  //
  //       Map<String, dynamic> data = change.doc.data() as Map<String, dynamic>;
  //         peerConnection?.addCandidate(RTCIceCandidate(
  //           data['candidate'],
  //           data['sdpMid'],
  //           data['sdpMLineIndex']
  //         ));
  //       }
  //     });
  //    });
  //
  //
  //
  // }
  //
  // joinRoom( String roomId) async{
  //
  //
  //     peerConnection = await createPeerConnection(configuration);
  //
  //     registerPeerConnectionListeners();
  //
  //   localStream?.getTracks().forEach((track) {
  //     print('track added');
  //       peerConnection?.addTrack(track, localStream!);
  //     });
  //
  //     registerPeerConnectionListeners();
  //
  //     DocumentSnapshot snapshot = await databaseServices.getSdpDoc(roomId);
  //     print("roomRef "+ snapshot.toString());
  //     var data = await snapshot.data() as Map<String ,dynamic>;
  //
  //     // var data = roomSnapshot.data() as Map<String ,dynamic>;
  //
  //
  //     peerConnection?.onIceCandidate = (RTCIceCandidate candidate){
  //
  //         databaseServices.
  //         setCalleeCandidate(roomId, candidate.toMap());
  //     };
  //
  //     registerPeerConnectionListeners();
  //      peerConnection!.onIceConnectionState = (e) {
  //     print('connectionState:'+ e.toString());
  //   };
  //
  //
  //     var offer = data['offer'];
  //
  //
  //
  //     await peerConnection?.setRemoteDescription(
  //       RTCSessionDescription(offer['sdp'], offer['type']));
  //
  //
  //     var answer = await peerConnection!.createAnswer();
  //
  //      print('answer:' + answer.toString());
  //
  //      databaseServices.addOfferOrAnswerSdp({"answer":answer.toMap()}, roomId);
  //
  //     await peerConnection!.setLocalDescription(answer!);
  //
  //     peerConnection?.onTrack = (RTCTrackEvent event) {
  //       print('Got remote track: ${event.streams[0]}');
  //       event.streams[0].getTracks().forEach((track) {
  //         print('Add a track to the remoteStream: $track');
  //         remoteStream?.addTrack(track);
  //       });
  //     };
  //
  //   CollectionReference callerCandidateCollectionRef = databaseServices.newCallerCandidateCheck(roomId);
  //
  //   callerCandidateCollectionRef.snapshots().listen((snapshot) {
  //     snapshot.docChanges.forEach((change) {
  //
  //       print("inside listen");
  //       if(change.type == DocumentChangeType.added){
  //         print("inside listen2");
  //       Map<String, dynamic> data = change.doc.data() as Map<String, dynamic>;
  //
  //       print('data+++++++'+data['candidate'].toString());
  //
  //
  //
  //         peerConnection?.addCandidate(RTCIceCandidate(
  //           data['candidate'],
  //           data['sdpMid'],
  //           data['sdpMLineIndex']
  //         ));
  //       }
  //     });
  //    });
  //
  // }
  //
  // Future<void> openUserMedia(
  // RTCVideoRenderer localVideo,
  // RTCVideoRenderer remoteVideo,
  // ) async {
  //   var stream = await navigator.mediaDevices
  //       .getUserMedia({'video': true, 'audio': false});
  //
  //   localVideo.srcObject = stream;
  //   localStream = stream;
  //
  //   remoteVideo.srcObject = await createLocalMediaStream('key');
  // }
  //
  // void hangUp(roomId, localVideo){
  //  databaseServices.deleteCaller(roomId);
  //  databaseServices.deleteCalleeCandidates(roomId);
  //  databaseServices.deleteCallerCandidates(roomId);
  //  databaseServices.deleteSdp(roomId);
  //  List<MediaStreamTrack> tracks = localVideo.srcObject!.getTracks();
  //   tracks.forEach((track) {
  //     track.stop();
  //   });
  //
  //   localStream!.dispose();
  //   remoteStream?.dispose();
  //
  //  // peerConnection!.close();
  // }
  //
  // void registerPeerConnectionListeners() {
  //   peerConnection?.onIceGatheringState = (RTCIceGatheringState state) {
  //     print('ICE gathering state changed: $state');
  //   };
  //
  //   peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
  //     print('Connection state change: $state');
  //   };
  //
  //   peerConnection?.onSignalingState = (RTCSignalingState state) {
  //     print('Signaling state change: $state');
  //   };
  //
  //   peerConnection?.onIceGatheringState = (RTCIceGatheringState state) {
  //     print('ICE connection state change: $state');
  //   };
  //
  //
  //   peerConnection?.onAddStream = (MediaStream stream) {
  //     print("Add remote stream");
  //     onAddRemoteStream?.call(stream);
  //     remoteStream = stream;
  //   };
  }
// }

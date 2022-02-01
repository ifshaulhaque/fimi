import 'package:fimi/views/HomePage/HomePage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:fimi/views/vidioCallingScreen/signaling.dart';

class VideoCallJoinScreen extends StatefulWidget {
  final String? roomId;
  VideoCallJoinScreen(this.roomId);

  @override
  _VideoCallJoinScreenState createState() => _VideoCallJoinScreenState();
}

class _VideoCallJoinScreenState extends State<VideoCallJoinScreen> {
final _localRanderer = new RTCVideoRenderer();
  var  _remoteRanderer = new RTCVideoRenderer();

Signaling signaling = new Signaling();


  @override
  void initState() {
    // TODO: implement initState
    // signaling.joinRoom(widget.roomId!);
    initRanderers();
    
    signaling.openUserMedia(_localRanderer, _remoteRanderer);
    signaling.onAddRemoteStream =((stream){
      _remoteRanderer.srcObject = stream;
      setState(() {
        
      });
    });
    super.initState();

  }
  @override
  dispose(){  
    _localRanderer.dispose();
    _remoteRanderer.dispose();
    super.dispose();
  }

  

  initRanderers() async{
    await _localRanderer.initialize();
    await _remoteRanderer.initialize();
  }
 

  @override
  Widget build(BuildContext context) {
    
    return Scaffold(
      appBar: AppBar(
        
        
      ),
      body: Stack(
        children: [
          

          Positioned(
            top:0,
            bottom:0,
            left:0,
            right:0,
            
            child: Container(
              
              child: RTCVideoView(_remoteRanderer),),),
              Positioned(
            top:0,
            left: 0,
            
            child: Container(
            width: 150,
            height: 170,
            child: RTCVideoView(_localRanderer,)
          ,)
          ,),
          Positioned(

            bottom: 20,
            left:0,
            right: 0,

            child:  InkWell(
              onTap: (){
                // signaling.hangUp(widget.roomId,_localRanderer);
               Navigator.pushReplacement(context,
                      MaterialPageRoute(builder: (context) => HomePage()));
              },
              child: CircleAvatar(
              foregroundColor: Colors.red,
              radius: 30,
              child: Icon(Icons.call_end)  ,
              ),
            ),
          )
        ],
        
      ) 
      
    );
  }
}

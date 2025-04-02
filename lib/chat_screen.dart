import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'login_screen.dart';

class ChatScreen extends StatefulWidget {
  final String chatRoomId;
  final String otherUserEmail;

  ChatScreen({required this.chatRoomId, required this.otherUserEmail});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;

    if (_currentUser == null) {
      // nếu null thì về lại LoginScreen
      Future.microtask(() {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => LoginScreen()),
        );
      });
    }
  }

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    await _firestore
        .collection('messages')
        .doc(widget.chatRoomId)
        .collection('chat')
        .add({
      'text': text,
      'sender': _currentUser?.email,
      'timestamp': FieldValue.serverTimestamp(),
    });

    _controller.clear();
    _scrollController.animateTo(
      0.0,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Colors.deepPurple;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: themeColor,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.grey[300],
              child: Icon(Icons.person, color: themeColor),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(widget.otherUserEmail, style: GoogleFonts.poppins(fontSize: 16)),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('messages')
                  .doc(widget.chatRoomId)
                  .collection('chat')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
                final messages = snapshot.data!.docs;

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg['sender'] == _currentUser?.email;

                    return Container(
                      margin: EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment:
                        isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        children: [
                          Text(
                            isMe ? "You" : msg['sender'],
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                          Container(
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                            padding: EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                            decoration: BoxDecoration(
                              color: isMe ? themeColor.withOpacity(0.2) : Colors.grey[300],
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(12),
                                topRight: Radius.circular(12),
                                bottomLeft: Radius.circular(isMe ? 12 : 0),
                                bottomRight: Radius.circular(isMe ? 0 : 12),
                              ),
                            ),
                            child: Text(
                              msg['text'],
                              style: GoogleFonts.poppins(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Divider(height: 1),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: themeColor,
                  child: IconButton(
                    icon: Icon(Icons.send, color: Colors.white),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

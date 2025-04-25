import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'login_screen.dart';

class ChatScreen extends StatefulWidget {
  final String chatRoomId;
  final String otherUserEmail;

  const ChatScreen({super.key, required this.chatRoomId, required this.otherUserEmail});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();
  final FocusNode _inputFocusNode = FocusNode();
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
    if (_currentUser == null) {
      Future.microtask(() {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => LoginScreen()),
        );
      });
    }
  }

  void _sendMessage({String? text, String? imageBase64}) async {
    if ((text == null || text.trim().isEmpty) && imageBase64 == null) return;

    final receiver = widget.otherUserEmail;
    final now = DateTime.now();

    final messageData = {
      'sender': _currentUser?.email,
      'receiver': receiver,
      'timestamp': FieldValue.serverTimestamp(),
      'localTimestamp': now.millisecondsSinceEpoch,
      'text': text ?? '',
      'image': imageBase64 ?? '',
    };

    await _firestore
        .collection('messages')
        .doc(widget.chatRoomId)
        .collection('chat')
        .add(messageData);

    await _firestore.collection('messages').doc(widget.chatRoomId).set({
      'lastMessage': text?.isNotEmpty == true ? text : '[Image]',
      'lastSender': _currentUser?.email,
      'lastReceiver': receiver,
      'timestamp': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    _controller.clear();
    _scrollController.animateTo(
      0.0,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      final base64Image = base64Encode(bytes);
      _sendMessage(imageBase64: base64Image);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color themeColor = const Color(0xFF3F51B5); // Indigo
    final Color accentColor = const Color(0xFFFFC107); // Amber
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

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
                  .orderBy('localTimestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
                final docs = snapshot.data!.docs;
                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final isMe = data['sender'] == _currentUser?.email;
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                        padding: EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isMe
                              ? themeColor.withOpacity(0.85)
                              : (isDark ? Colors.grey[700] : Colors.grey[300]),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: data['image'] != ''
                            ? GestureDetector(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (_) => Dialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                child: Container(
                                  padding: EdgeInsets.all(10),
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.of(context).size.width * 0.8,
                                    maxHeight: MediaQuery.of(context).size.height * 0.8,
                                  ),
                                  child: Image.memory(
                                    base64Decode(data['image']),
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            );
                          },
                          child: Image.memory(
                            base64Decode(data['image']),
                            width: MediaQuery.of(context).size.width * 0.6,
                            height: 200,
                            fit: BoxFit.cover,
                          ),
                        )
                            : Text(
                          data['text'] ?? '',
                          style: TextStyle(color: isMe ? Colors.white : Colors.black87),
                        ),
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
            color: isDark ? Colors.grey[850] : Colors.white,
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.image, color: accentColor),
                  onPressed: _pickImage,
                ),
                Expanded(
                  child: RawKeyboardListener(
                    focusNode: _inputFocusNode,
                    onKey: (event) {
                      if (event is RawKeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.enter) {
                        if (event.isShiftPressed) {
                          final text = _controller.text;
                          final selection = _controller.selection;
                          final newText = text.replaceRange(selection.start, selection.end, '\n');
                          _controller.text = newText;
                          _controller.selection = TextSelection.fromPosition(
                            TextPosition(offset: selection.start + 1),
                          );
                        } else {
                          _sendMessage(text: _controller.text.trim());
                          _controller.clear();
                        }
                      }
                    },
                    child: TextField(
                      controller: _controller,
                      keyboardType: TextInputType.multiline,
                      maxLines: null,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: themeColor,
                  child: IconButton(
                    icon: Icon(Icons.send, color: Colors.white),
                    onPressed: () {
                      _sendMessage(text: _controller.text.trim());
                      _controller.clear();
                    },
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

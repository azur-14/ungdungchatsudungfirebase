import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import 'chat_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _searchController = TextEditingController();
  final _notificationsPlugin = FlutterLocalNotificationsPlugin();
  User get currentUser => _auth.currentUser!;

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _createUserIfNotExist();
    _listenToFriendRequests();
    _listenToIncomingMessages();
  }

  void _initializeNotifications() {
    const AndroidInitializationSettings initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    final settings = InitializationSettings(android: initAndroid);
    _notificationsPlugin.initialize(settings);
  }

  void _showNotification(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'chat_channel',
      'Chat Notifications',
      importance: Importance.max,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    await _notificationsPlugin.show(0, title, body, details);
  }

  Future<void> _createUserIfNotExist() async {
    final doc = await _firestore.collection('users').doc(currentUser.uid).get();
    if (!doc.exists) {
      await _firestore.collection('users').doc(currentUser.uid).set({
        'email': currentUser.email,
        'friends': [],
        'friend_requests': [],
        'pending_sent_requests': [],
      });
    }
  }
  void _listenToFriendRequests() {
    _firestore.collection('users').doc(currentUser.uid).snapshots().listen((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final List requests = data['friend_requests'] ?? [];
      if (requests.isNotEmpty) {
        _showNotification('New Friend Request', 'You have a new friend request!');
      }
    });
  }

  void _listenToIncomingMessages() {
    _firestore
        .collection('messages')
        .where('participants', arrayContains: currentUser.uid)
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docs) {
        final lastSender = doc['lastSender'];
        final lastMessage = doc['lastMessage'];
        if (lastSender != currentUser.email) {
          _showNotification('New Message', lastMessage ?? '[Image]');
        }
      }
    });
  }

  void _searchAndSendRequest() async {
    final email = _searchController.text.trim();
    if (email.isEmpty || email == currentUser.email) return;

    final result = await _firestore.collection('users').where('email', isEqualTo: email).get();
    if (result.docs.isEmpty) {
      _showSnack('User not found');
      return;
    }

    final targetUid = result.docs.first.id;
    final currentRef = _firestore.collection('users').doc(currentUser.uid);
    final targetRef = _firestore.collection('users').doc(targetUid);

    final currentDoc = await currentRef.get();
    final targetDocSnap = await targetRef.get();

    List sent = List.from(currentDoc['pending_sent_requests'] ?? []);
    List received = List.from(currentDoc['friend_requests'] ?? []);
    List friends = List.from(currentDoc['friends'] ?? []);

    if (friends.contains(targetUid)) return _showSnack('Already friends');
    if (received.contains(targetUid)) return _showSnack('They already sent you a request');
    if (sent.contains(targetUid)) return _showSnack('Request already sent');

    sent.add(targetUid);
    List targetReceived = List.from(targetDocSnap['friend_requests'] ?? []);
    targetReceived.add(currentUser.uid);

    await currentRef.update({'pending_sent_requests': sent});
    await targetRef.update({'friend_requests': targetReceived});
    _showSnack('Friend request sent');
    _searchController.clear();
  }
  Widget _buildFriendRequests() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('users').doc(currentUser.uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return CircularProgressIndicator();
        final data = snapshot.data!.data() as Map<String, dynamic>;
        final List requests = data['friend_requests'] ?? [];

        if (requests.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text("No friend requests", style: GoogleFonts.poppins(color: Colors.grey)),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Text("Friend Requests", style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            ...requests.map((uid) => FutureBuilder<DocumentSnapshot>(
              future: _firestore.collection('users').doc(uid).get(),
              builder: (context, snap) {
                if (!snap.hasData) return SizedBox.shrink();
                String email = snap.data?['email'] ?? '';
                return ListTile(
                  leading: Icon(Icons.person),
                  title: Text(email),
                  trailing: ElevatedButton(
                    onPressed: () => _acceptFriend(uid),
                    child: Text("Accept"),
                  ),
                );
              },
            )),
          ],
        );
      },
    );
  }

  Widget _buildPendingSentRequests() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('users').doc(currentUser.uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return CircularProgressIndicator();
        final data = snapshot.data!.data() as Map<String, dynamic>;
        final List sentRequests = data['pending_sent_requests'] ?? [];

        if (sentRequests.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text("No pending friend requests", style: GoogleFonts.poppins(color: Colors.grey)),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Text("Pending Friend Requests", style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            ...sentRequests.map((uid) => FutureBuilder<DocumentSnapshot>(
              future: _firestore.collection('users').doc(uid).get(),
              builder: (context, snap) {
                if (!snap.hasData) return SizedBox.shrink();
                String email = snap.data?['email'] ?? '';
                return ListTile(
                  leading: Icon(Icons.hourglass_top),
                  title: Text(email),
                  trailing: IconButton(
                    icon: Icon(Icons.cancel, color: Colors.red),
                    onPressed: () => _cancelSentRequest(uid),
                    tooltip: "Cancel request",
                  ),
                );
              },
            )),
          ],
        );
      },
    );
  }
  void _cancelSentRequest(String targetUid) async {
    final userRef = _firestore.collection('users').doc(currentUser.uid);
    final targetRef = _firestore.collection('users').doc(targetUid);
    final userDoc = await userRef.get();
    final targetDoc = await targetRef.get();

    List sent = List.from(userDoc['pending_sent_requests'] ?? []);
    List received = List.from(targetDoc['friend_requests'] ?? []);

    sent.remove(targetUid);
    received.remove(currentUser.uid);

    await userRef.update({'pending_sent_requests': sent});
    await targetRef.update({'friend_requests': received});
    _showSnack('Request cancelled');
  }

  void _acceptFriend(String requesterUid) async {
    final userRef = _firestore.collection('users').doc(currentUser.uid);
    final requesterRef = _firestore.collection('users').doc(requesterUid);
    final userDoc = await userRef.get();
    final requesterDoc = await requesterRef.get();

    List myFriends = List.from(userDoc['friends'] ?? []);
    List myRequests = List.from(userDoc['friend_requests'] ?? []);
    List requesterFriends = List.from(requesterDoc['friends'] ?? []);
    List requesterSent = List.from(requesterDoc['pending_sent_requests'] ?? []);

    myFriends.add(requesterUid);
    requesterFriends.add(currentUser.uid);

    myRequests.remove(requesterUid);
    requesterSent.remove(currentUser.uid);

    await userRef.update({'friends': myFriends, 'friend_requests': myRequests});
    await requesterRef.update({'friends': requesterFriends, 'pending_sent_requests': requesterSent});
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await FirebaseAuth.instance.signOut();
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LoginScreen()));
  }
  void _goToChat(String friendUid, String friendEmail) {
    if (friendUid == currentUser.uid) {
      print("Error: friendUid is the same as current user UID.");
      return;
    }
    final ids = [currentUser.uid, friendUid]..sort();
    final chatRoomId = ids.join("_");
    print("Navigating to chat room with chatRoomId: $chatRoomId");
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatRoomId: chatRoomId,
          otherUserEmail: friendEmail,
        ),
      ),
    );
  }

  Stream<List<Map<String, dynamic>>> _allFriendsWithLastMessage() async* {
    yield* _firestore
        .collection('users')
        .doc(currentUser.uid)
        .snapshots()
        .asyncMap((userSnap) async {
      final raw = userSnap.data();
      if (raw == null) return [];

      final data = raw;
      final List<dynamic> friendIds = data['friends'] ?? [];
      final List<Map<String, dynamic>> results = [];

      for (String friendUid in friendIds) {
        try {
          final userDoc = await _firestore.collection('users').doc(friendUid).get();
          if (!userDoc.exists) continue;

          final ids = [currentUser.uid, friendUid]..sort();
          final chatRoomId = ids.join('_');
          final messageSnap = await _firestore.collection('messages').doc(chatRoomId).get();

          String lastMessage = '';
          String lastSender = '';

          if (messageSnap.exists) {
            final messageData = messageSnap.data();
            lastMessage = messageData?['lastMessage'] ?? '';
            lastSender = messageData?['lastSender'] ?? '';
          }

          results.add({
            'chatRoomId': chatRoomId,
            'friendEmail': userDoc['email'],
            'friendUid': friendUid,
            'lastMessage': lastMessage,
            'lastSender': lastSender,
          });
        } catch (e) {
          print("Error loading friend $friendUid: $e");
          continue;
        }
      }

      return results;
    });
  }
  @override
  Widget build(BuildContext context) {
    final Color themeColor = const Color(0xFF3F51B5); // Indigo
    final Color accentColor = const Color(0xFFFFC107); // Amber
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color cardColor = isDark ? Colors.grey[900]! : Colors.white;
    final Color iconColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text("My Chat", style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600)),
        backgroundColor: themeColor,
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: _logout,
            tooltip: "Logout",
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(12),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search by email',
                  prefixIcon: Icon(Icons.search),
                  suffixIcon: Container(
                    margin: EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: themeColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      icon: Icon(Icons.person_add_alt_1, color: Colors.white),
                      onPressed: _searchAndSendRequest,
                      tooltip: "Send friend request",
                    ),
                  ),
                  filled: true,
                  fillColor: cardColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
            ),
          ),

          Divider(),
          _buildFriendRequests(),
          Divider(),
          _buildPendingSentRequests(),
          Divider(),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              children: [
                Text("Your Friends", style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
          ),

          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _allFriendsWithLastMessage(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
                final chats = snapshot.data!;
                if (chats.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, color: Colors.grey, size: 48),
                        SizedBox(height: 12),
                        Text("No conversations yet.", style: GoogleFonts.poppins(color: Colors.grey)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: chats.length,
                  itemBuilder: (context, index) {
                    final chat = chats[index];
                    final isUnread = chat['lastSender'] != currentUser.email &&
                        (chat['lastMessage'] ?? '').toString().trim().isNotEmpty;

                    return Card(
                      color: isUnread ? themeColor.withOpacity(0.05) : cardColor,
                      shape: RoundedRectangleBorder(
                        side: isUnread
                            ? BorderSide(color: themeColor, width: 1.5)
                            : BorderSide.none,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      elevation: isUnread ? 4 : 1,
                      child: ListTile(
                        leading: Stack(
                          children: [
                            CircleAvatar(
                              backgroundColor: themeColor,
                              child: Icon(Icons.person, color: Colors.white),
                            ),
                            if (isUnread)
                              Positioned(
                                right: 0,
                                top: 0,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Text(chat['friendEmail'], style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                        subtitle: Text(
                          (chat['lastMessage'] ?? '').toString().trim().isEmpty
                              ? 'No messages yet'
                              : chat['lastMessage'],
                          style: GoogleFonts.poppins(
                            fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
                            color: isUnread
                                ? (isDark ? Colors.white : Colors.black87)
                                : (isDark ? Colors.grey[400]! : Colors.black54),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Icon(Icons.chat, color: themeColor),
                        onTap: () => _goToChat(chat['friendUid'], chat['friendEmail']),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

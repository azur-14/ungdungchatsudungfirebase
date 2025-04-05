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
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

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
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    final InitializationSettings initializationSettings =
    InitializationSettings(android: initializationSettingsAndroid);
    _notificationsPlugin.initialize(initializationSettings);
  }

  void _showNotification(String title, String body) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'channel_id',
      'Chat Notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    const NotificationDetails platformDetails = NotificationDetails(android: androidDetails);
    await _notificationsPlugin.show(0, title, body, platformDetails);
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
    _firestore.collection('messages').snapshots().listen((snapshot) {
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
    if (email.isEmpty) return;

    if (email == currentUser.email) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("You cannot send a friend request to yourself."),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }

    final result = await _firestore.collection('users').where('email', isEqualTo: email).get();
    if (result.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('User not found')));
      return;
    }

    final targetDoc = result.docs.first;
    final targetUid = targetDoc.id;

    final currentDocRef = _firestore.collection('users').doc(currentUser.uid);
    final targetDocRef = _firestore.collection('users').doc(targetUid);

    final currentDoc = await currentDocRef.get();
    final targetDocSnapshot = await targetDocRef.get();

    List sent = List.from(currentDoc['pending_sent_requests'] ?? []);
    List received = List.from(currentDoc['friend_requests'] ?? []);
    List friends = List.from(currentDoc['friends'] ?? []);

    if (friends.contains(targetUid)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('You are already friends')));
      return;
    }

    if (received.contains(targetUid)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('This user has already sent you a friend request')));
      return;
    }

    if (sent.contains(targetUid)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Friend request already sent')));
      return;
    }

    sent.add(targetUid);
    List targetReceived = List.from(targetDocSnapshot['friend_requests'] ?? []);
    targetReceived.add(currentUser.uid);

    await currentDocRef.update({'pending_sent_requests': sent});
    await targetDocRef.update({'friend_requests': targetReceived});

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Friend request sent')));
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

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Friend request cancelled')));
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

  // FIXED: Sử dụng UID và sắp xếp chúng để tạo chatRoomId duy nhất
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

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await FirebaseAuth.instance.signOut();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Colors.deepPurple;

    return Scaffold(
      backgroundColor: Colors.grey[100],
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
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by email',
                prefixIcon: Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: Icon(Icons.person_add_alt_1),
                  onPressed: _searchAndSendRequest,
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white,
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
                Text("Your Friends", style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500)),
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
                  return Center(child: Text("No conversations yet.", style: GoogleFonts.poppins(color: Colors.grey)));
                }

                return ListView.builder(
                  itemCount: chats.length,
                  itemBuilder: (context, index) {
                    final chat = chats[index];
                    final isUnread = chat['lastSender'] != currentUser.email;

                    return Card(
                      color: isUnread ? Colors.deepPurple[50] : Colors.white,
                      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      elevation: 2,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: themeColor,
                          child: Icon(Icons.person, color: Colors.white),
                        ),
                        title: Text(chat['friendEmail'], style: GoogleFonts.poppins()),
                        subtitle: Text(
                          (chat['lastMessage'] ?? '').toString().trim().isEmpty
                              ? 'No messages yet'
                              : chat['lastMessage'],
                          style: GoogleFonts.poppins(
                            fontStyle: (chat['lastMessage'] ?? '').toString().trim().isEmpty
                                ? FontStyle.italic
                                : FontStyle.normal,
                            color: (chat['lastMessage'] ?? '').toString().trim().isEmpty
                                ? Colors.grey
                                : Colors.black,
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

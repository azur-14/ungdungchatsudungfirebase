import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import 'chat_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _searchController = TextEditingController();

  User get currentUser => _auth.currentUser!;

  @override
  void initState() {
    super.initState();
    _createUserIfNotExist();
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

  void _searchAndSendRequest() async {
    final email = _searchController.text.trim();
    if (email.isEmpty || email == currentUser.email) return;

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
    List received = List.from(targetDocSnapshot['friend_requests'] ?? []);
    List friends = List.from(currentDoc['friends'] ?? []);

    if (friends.contains(targetUid)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('You are already friends')));
      return;
    }

    if (sent.contains(targetUid)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Friend request already sent')));
      return;
    }

    sent.add(targetUid);
    received.add(currentUser.uid);

    await currentDocRef.update({'pending_sent_requests': sent});
    await targetDocRef.update({'friend_requests': received});

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Friend request sent')));
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

  void _goToChat(String friendUid, String friendEmail) {
    final ids = [currentUser.uid, friendUid]..sort();
    final chatRoomId = ids.join("_");
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

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await FirebaseAuth.instance.signOut();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => LoginScreen()),
    );
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

  Future<List<Map<String, dynamic>>> _fetchFriendList(List<dynamic> ids) async {
    final List<Map<String, dynamic>> results = [];
    for (String id in ids) {
      final doc = await _firestore.collection('users').doc(id).get();
      if (doc.exists) {
        results.add({'uid': id, 'email': doc['email']});
      }
    }
    return results;
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              children: [
                Text("Your Friends", style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: _firestore.collection('users').doc(currentUser.uid).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return Center(child: CircularProgressIndicator());

                final data = snapshot.data!.data() as Map<String, dynamic>;
                final List<dynamic> friendIds = data['friends'] ?? [];

                if (friendIds.isEmpty) {
                  return Center(child: Text("No friends yet.", style: GoogleFonts.poppins(color: Colors.grey)));
                }

                return FutureBuilder<List<Map<String, dynamic>>>(
                  future: _fetchFriendList(friendIds),
                  builder: (context, snap) {
                    if (!snap.hasData) return Center(child: CircularProgressIndicator());

                    final friends = snap.data!;
                    return ListView.builder(
                      itemCount: friends.length,
                      itemBuilder: (context, index) {
                        final friend = friends[index];
                        return Card(
                          margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          elevation: 2,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: themeColor,
                              child: Icon(Icons.person, color: Colors.white),
                            ),
                            title: Text(friend['email'], style: GoogleFonts.poppins()),
                            trailing: Icon(Icons.chat, color: themeColor),
                            onTap: () => _goToChat(friend['uid'], friend['email']),
                          ),
                        );
                      },
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

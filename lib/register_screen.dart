import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _auth = FirebaseAuth.instance;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  void _register() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    setState(() => _isLoading = true);
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(email: email, password: password);

      await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
        'email': email,
        'friends': [],
        'friend_requests': [],
        'pending_sent_requests': [],
      });

      await userCredential.user!.sendEmailVerification();

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text("Verify Email"),
          content: Text("A verification email has been sent to $email."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LoginScreen())),
              child: Text("OK"),
            ),
          ],
        ),
      );
    } catch (e) {
      _showError("Registration failed: ${e.toString()}");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color themeColor = const Color(0xFF3F51B5); // Indigo
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[100],
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_add_alt_1_rounded, size: 80, color: themeColor),
                SizedBox(height: 16),
                Text("Create Account",
                    style: GoogleFonts.poppins(
                        fontSize: 30, fontWeight: FontWeight.bold, color: themeColor)),
                SizedBox(height: 30),
                Card(
                  elevation: 10,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildTextForm("Email", _emailController, Icons.email, false, validator: (val) {
                            if (val == null || val.isEmpty) return 'Enter email';
                            if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(val)) return 'Invalid email';
                            return null;
                          }),
                          SizedBox(height: 16),
                          _buildTextForm("Password", _passwordController, Icons.lock, true, obscureKey: "_obscurePassword", validator: (val) {
                            if (val == null || val.isEmpty) return 'Enter password';
                            if (val.length < 6) return 'Min 6 characters';
                            return null;
                          }),
                          SizedBox(height: 16),
                          _buildTextForm("Confirm Password", _confirmPasswordController, Icons.lock_outline, true, obscureKey: "_obscureConfirm", validator: (val) {
                            if (val == null || val.isEmpty) return 'Confirm password';
                            if (val != _passwordController.text) return 'Passwords do not match';
                            return null;
                          }),
                          SizedBox(height: 24),
                          _isLoading
                              ? Center(child: CircularProgressIndicator())
                              : ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: themeColor,
                              padding: EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _register,
                            child: Text(
                              "Register",
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white, // 👈 Bắt buộc chỉ định rõ ràng
                              ),
                            ),
                          ),
                          SizedBox(height: 16),
                          Center(
                            child: TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text("Already have an account? Login",
                                  style: GoogleFonts.poppins(
                                      color: themeColor,
                                      fontWeight: FontWeight.w500,
                                      decoration: TextDecoration.underline)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextForm(String label, TextEditingController controller, IconData icon,
      bool obscure, {
        String? Function(String?)? validator,
        String obscureKey = "",
      }) {
    bool isObscure = obscureKey == "_obscurePassword" ? _obscurePassword : _obscureConfirm;

    return TextFormField(
      controller: controller,
      obscureText: obscure ? isObscure : false,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Theme.of(context).cardColor,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        suffixIcon: obscure
            ? IconButton(
          icon: Icon(isObscure ? Icons.visibility : Icons.visibility_off),
          onPressed: () => setState(() {
            if (obscureKey == "_obscurePassword") {
              _obscurePassword = !_obscurePassword;
            } else {
              _obscureConfirm = !_obscureConfirm;
            }
          }),
        )
            : null,
      ),
      validator: validator,
    );
  }
}

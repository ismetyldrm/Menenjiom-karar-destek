import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'patient_list_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isLoading = false;
  final ApiService _apiService = ApiService();

  void _handleLogin() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Lütfen kullanıcı adı ve şifre alanlarını doldurun.")));
      return;
    }
    setState(() => _isLoading = true);
    var result = await _apiService.login(
        _usernameController.text, _passwordController.text);
    setState(() => _isLoading = false);

    if (result != null && result['status'] == 'success') {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (context) => const PatientListScreen()));
    } else {
      showDialog(
          context: context,
          builder: (context) => AlertDialog(
              title: const Text("Giriş Başarısız"),
              content: Text(
                  result?['message'] ?? "Kullanıcı adı veya şifre hatalı.")));
    }
  }

  // --- GÜNCELLENEN ŞİFRE SIFIRLAMA AKIŞI ---
  void _showForgotPasswordDialog(BuildContext context) {
    final TextEditingController emailController = TextEditingController();
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Şifre Sıfırlama'),
              content: TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                      labelText: 'E-Posta Adresi',
                      prefixIcon: Icon(Icons.email, color: Colors.teal))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('İptal')),
                ElevatedButton(
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                    onPressed: () async {
                      String email = emailController.text.trim();
                      if (email.isEmpty) return;

                      // İstek sürecinde kullanıcıya bilgi ver
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Kod gönderiliyor, bekleyin...')));

                      var result = await _apiService.forgotPassword(email);

                      if (context.mounted) {
                        Navigator.pop(context); // Diyalogu kapat
                        if (result != null && result['status'] == 'success') {
                          _showResetPasswordDialog(context, email);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content:
                                  Text(result?['message'] ?? 'Hata oluştu!')));
                        }
                      }
                    },
                    child: const Text('Gönder',
                        style: TextStyle(color: Colors.white))),
              ],
            ));
  }

  void _showResetPasswordDialog(BuildContext context, String email) {
    final TextEditingController token = TextEditingController();
    final TextEditingController pass = TextEditingController();
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
              title: const Text('Yeni Şifre'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: token,
                    decoration: const InputDecoration(labelText: 'Kod')),
                TextField(
                    controller: pass,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Yeni Şifre')),
              ]),
              actions: [
                ElevatedButton(
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                    onPressed: () async {
                      var res = await _apiService.resetPassword(
                          email, token.text, pass.text);
                      if (context.mounted &&
                          res != null &&
                          res['status'] == 'success') {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Şifre güncellendi!'),
                                backgroundColor: Colors.green));
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(res?['message'] ?? 'Hata!'),
                            backgroundColor: Colors.red));
                      }
                    },
                    child: const Text('Yenile',
                        style: TextStyle(color: Colors.white))),
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Row(
        children: [
          Expanded(
              flex: 4,
              child: Center(
                  child: SingleChildScrollView(
                      child: Container(
                padding: const EdgeInsets.all(40.0),
                constraints: const BoxConstraints(maxWidth: 450),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.local_hospital,
                        size: 60, color: Colors.teal),
                    const SizedBox(height: 20),
                    const Text("Menenjiom Karar Destek",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF2D3748))),
                    const SizedBox(height: 8),
                    const Text("Hoş geldiniz, lütfen kimliğinizi doğrulayın.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 14)),
                    const SizedBox(height: 40),
                    _buildTextField(_usernameController, "Kullanıcı Adı",
                        Icons.person_rounded, false),
                    const SizedBox(height: 20),
                    _buildTextField(_passwordController, "Şifre",
                        Icons.lock_rounded, !_isPasswordVisible,
                        suffix: IconButton(
                            icon: Icon(_isPasswordVisible
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () => setState(() =>
                                _isPasswordVisible = !_isPasswordVisible))),
                    Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                            onPressed: () => _showForgotPasswordDialog(context),
                            child: const Text("Şifremi Unuttum?",
                                style: TextStyle(
                                    color: Colors.teal,
                                    fontWeight: FontWeight.bold)))),
                    const SizedBox(height: 30),
                    ElevatedButton(
                        onPressed: _isLoading ? null : _handleLogin,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15))),
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : const Text("GÜVENLİ GİRİŞ YAP",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white))),
                  ],
                ),
              )))),
          Expanded(
              flex: 6,
              child: Container(
                  decoration: const BoxDecoration(
                      image: DecorationImage(
                          image: NetworkImage(
                              "https://images.pexels.com/photos/305565/pexels-photo-305565.jpeg?auto=compress&cs=tinysrgb&w=1260&h=750&dpr=1"),
                          fit: BoxFit.cover)),
                  child: Container(
                      decoration: BoxDecoration(
                          gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                            const Color(0xFFF5F7FA),
                            Colors.teal.withOpacity(0.2),
                            Colors.teal.withOpacity(0.6)
                          ])),
                      child: const Padding(
                          padding: EdgeInsets.all(40.0),
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text("Yapay Zeka Destekli\nRadyoloji Asistanı",
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 36,
                                        fontWeight: FontWeight.bold,
                                        shadows: [
                                          Shadow(
                                              offset: Offset(2, 2),
                                              blurRadius: 10.0,
                                              color: Colors.black45)
                                        ]))
                              ]))))),
        ],
      ),
    );
  }

  Widget _buildTextField(
      TextEditingController ctrl, String label, IconData icon, bool obscure,
      {Widget? suffix}) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 2,
                blurRadius: 10,
                offset: const Offset(0, 3))
          ]),
      child: TextField(
          controller: ctrl,
          obscureText: obscure,
          decoration: InputDecoration(
              labelText: label,
              prefixIcon: Icon(icon, color: Colors.teal),
              suffixIcon: suffix,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 20))),
    );
  }
}

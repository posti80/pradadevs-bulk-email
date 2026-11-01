import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const violet = Color(0xFF9B72FF);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PRADADEVS Bulk Email',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090812),
        colorScheme: ColorScheme.fromSeed(
          seedColor: violet,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF171426),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF302747)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: violet, width: 1.5),
          ),
        ),
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  static const _storage = FlutterSecureStorage();

  final _emailController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '587');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fromNameController = TextEditingController(text: 'PRADADEVS');
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();

  final List<String> _recipients = [];

  bool _ssl = false;
  bool _loading = true;
  bool _sending = false;
  bool _showPassword = false;
  int _sent = 0;
  int _failed = 0;
  String _status = 'Bereit';
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _fromNameController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    _recipients.addAll(prefs.getStringList('recipients') ?? []);
    _hostController.text = prefs.getString('smtp_host') ?? '';
    _portController.text = prefs.getString('smtp_port') ?? '587';
    _usernameController.text = prefs.getString('smtp_user') ?? '';
    _fromNameController.text =
        prefs.getString('from_name') ?? 'PRADADEVS';
    _ssl = prefs.getBool('smtp_ssl') ?? false;
    _subjectController.text = prefs.getString('subject') ?? '';
    _messageController.text = prefs.getString('message') ?? '';

    _passwordController.text =
        await _storage.read(key: 'smtp_password') ?? '';

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setStringList('recipients', _recipients);
    await prefs.setString('smtp_host', _hostController.text.trim());
    await prefs.setString('smtp_port', _portController.text.trim());
    await prefs.setString('smtp_user', _usernameController.text.trim());
    await prefs.setString('from_name', _fromNameController.text.trim());
    await prefs.setBool('smtp_ssl', _ssl);
    await prefs.setString('subject', _subjectController.text);
    await prefs.setString('message', _messageController.text);

    await _storage.write(
      key: 'smtp_password',
      value: _passwordController.text,
    );
  }

  bool _validEmail(String email) {
    return RegExp(
      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
    ).hasMatch(email.trim());
  }

  Future<void> _addEmail() async {
    final email = _emailController.text.trim().toLowerCase();

    if (!_validEmail(email)) {
      _showMessage('Bitte gib eine gültige E-Mail-Adresse ein.');
      return;
    }

    if (_recipients.contains(email)) {
      _showMessage('Diese Adresse ist bereits vorhanden.');
      return;
    }

    setState(() {
      _recipients.add(email);
      _emailController.clear();
    });

    await _saveSettings();
  }

  Future<void> _removeEmail(String email) async {
    setState(() => _recipients.remove(email));
    await _saveSettings();
  }

  Future<void> _importFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'csv'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes;

      if (bytes == null) {
        _showMessage('Die Datei konnte nicht gelesen werden.');
        return;
      }

      final extension = file.extension?.toLowerCase();
      final List<String> found = [];

      if (extension == 'xlsx') {
        final workbook = xls.Excel.decodeBytes(bytes);

        if (workbook.tables.isEmpty) {
          _showMessage('Die Excel-Datei enthält kein Tabellenblatt.');
          return;
        }

        final sheet = workbook.tables[workbook.tables.keys.first]!;

        for (final row in sheet.rows) {
          for (final cell in row) {
            final value = cell?.value?.toString().trim() ?? '';

            if (_validEmail(value)) {
              found.add(value.toLowerCase());
            }
          }
        }
      } else if (extension == 'csv') {
        final content = utf8.decode(bytes, allowMalformed: true);
        final firstLine = content.split('\n').first;
        final delimiter = firstLine.contains(';') ? ';' : ',';

        final rows = const CsvToListConverter().convert(
          content,
          fieldDelimiter: delimiter,
        );

        for (final row in rows) {
          for (final value in row) {
            final email = value.toString().trim();

            if (_validEmail(email)) {
              found.add(email.toLowerCase());
            }
          }
        }
      } else {
        _showMessage('Bitte eine XLSX- oder CSV-Datei auswählen.');
        return;
      }

      int added = 0;

      setState(() {
        for (final email in found) {
          if (!_recipients.contains(email)) {
            _recipients.add(email);
            added++;
          }
        }
      });

      await _saveSettings();

      _showMessage(
        '$added neue Adressen importiert. '
        '${found.length - added} bereits vorhanden oder doppelt.',
      );
    } catch (e) {
      _showMessage('Importfehler: $e');
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: const Color(0xFF302747),
      ),
    );
  }

  String? _validateSmtp() {
    if (_hostController.text.trim().isEmpty) {
      return 'Bitte SMTP-Server/Host eintragen.';
    }

    final port = int.tryParse(_portController.text.trim());

    if (port == null || port < 1 || port > 65535) {
      return 'Bitte einen gültigen SMTP-Port eintragen.';
    }

    if (_usernameController.text.trim().isEmpty) {
      return 'Bitte SMTP-Benutzername eintragen.';
    }

    if (_passwordController.text.isEmpty) {
      return 'Bitte SMTP-Passwort eintragen.';
    }

    if (!_validEmail(_usernameController.text.trim())) {
      return 'Der SMTP-Benutzername muss eine E-Mail-Adresse sein.';
    }

    return null;
  }

  Future<void> _sendEmails() async {
    if (_sending) return;

    if (_recipients.isEmpty) {
      _showMessage('Bitte zuerst Empfänger hinzufügen.');
      return;
    }

    final smtpError = _validateSmtp();

    if (smtpError != null) {
      _showMessage(smtpError);
      return;
    }

    if (_subjectController.text.trim().isEmpty ||
        _messageController.text.trim().isEmpty) {
      _showMessage('Bitte Betreff und Nachricht ausfüllen.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Versand bestätigen'),
        content: Text(
          'Es werden ${_recipients.length} E-Mails einzeln versendet. '
          'Bitte bestätige, dass alle Empfänger dem Erhalt zugestimmt haben.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Jetzt senden'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _saveSettings();

    final port = int.parse(_portController.text.trim());

    final server = SmtpServer(
      _hostController.text.trim(),
      port: port,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      ssl: _ssl,
    );

    final sender = _usernameController.text.trim();
    final senderName = _fromNameController.text.trim().isEmpty
        ? 'PRADADEVS'
        : _fromNameController.text.trim();

    setState(() {
      _sending = true;
      _sent = 0;
      _failed = 0;
      _progress = 0;
      _status = 'Versand wird vorbereitet ...';
    });

    final recipients = List<String>.from(_recipients);

    for (int i = 0; i < recipients.length; i++) {
      final recipient = recipients[i];

      try {
        final email = Message()
          ..from = Address(sender, senderName)
          ..recipients.add(recipient)
          ..subject = _subjectController.text.trim()
          ..text = _messageController.text;

        await send(email, server);
        _sent++;
      } catch (e) {
        _failed++;
      }

      if (!mounted) return;

      setState(() {
        _progress = (i + 1) / recipients.length;
        _status = 'Bearbeitet: ${i + 1} von ${recipients.length}';
      });
    }

    if (!mounted) return;

    setState(() {
      _sending = false;
      _status = 'Versand abgeschlossen';
    });

    _showMessage(
      'Fertig: $_sent erfolgreich, $_failed fehlgeschlagen.',
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 22),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFB99BFF)),
          const SizedBox(width: 9),
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    bool obscure = false,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
        ),
      ),
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF11101D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF302747)),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'PRADADEVS',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: false,
        backgroundColor: const Color(0xFF090812),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                'Pradadevvs',
                style: TextStyle(
                  color: Color(0xFFB99BFF),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
          children: [
            _panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'BULK EMAIL',
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Dein E-Mail-Versand. Deine Kontrolle.',
                    style: TextStyle(color: Colors.white60),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _stat(
                          'Empfänger',
                          '${_recipients.length}',
                          Icons.people_alt_outlined,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _stat(
                          'Gesendet',
                          '$_sent',
                          Icons.check_circle_outline,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _stat(
                          'Fehler',
                          '$_failed',
                          Icons.error_outline,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            _sectionTitle('Empfänger', Icons.people_outline),
            _panel(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'E-Mail-Adresse',
                            hintText: 'name@beispiel.de',
                          ),
                          onSubmitted: (_) => _addEmail(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _sending ? null : _addEmail,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _sending ? null : _importFile,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Excel / CSV importieren'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_recipients.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Noch keine Empfänger hinzugefügt.',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  else
                    ..._recipients.map(
                      (email) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.mail_outline,
                          color: Color(0xFFB99BFF),
                        ),
                        title: Text(
                          email,
                          style: const TextStyle(fontSize: 13),
                        ),
                        trailing: IconButton(
                          onPressed: _sending
                              ? null
                              : () => _removeEmail(email),
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                          ),
                        ),
                      ),
                    ),
                  if (_recipients.isNotEmpty)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _sending
                            ? null
                            : () async {
                                setState(() => _recipients.clear());
                                await _saveSettings();
                              },
                        child: const Text('Alle entfernen'),
                      ),
                    ),
                ],
              ),
            ),

            _sectionTitle('SMTP-Einstellungen', Icons.dns_outlined),
            _panel(
              child: Column(
                children: [
                  _field(
                    'SMTP-Server / Host',
                    _hostController,
                    hint: 'mail.deinserver.de',
                  ),
                  _field(
                    'Port',
                    _portController,
                    keyboardType: TextInputType.number,
                    hint: '587',
                  ),
                  _field(
                    'SMTP-Benutzername / E-Mail',
                    _usernameController,
                    hint: 'absender@deinedomain.de',
                  ),
                  TextField(
                    controller: _passwordController,
                    obscureText: !_showPassword,
                    decoration: InputDecoration(
                      labelText: 'SMTP-Passwort',
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() => _showPassword = !_showPassword);
                        },
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _field(
                    'Absendername',
                    _fromNameController,
                    hint: 'PRADADEVS',
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('SSL / TLS-Verbindung'),
                    subtitle: Text(
                      _ssl ? 'SSL aktiviert' : 'SSL deaktiviert',
                    ),
                    value: _ssl,
                    onChanged: _sending
                        ? null
                        : (value) => setState(() => _ssl = value),
                  ),
                  const Text(
                    'Typische Einstellungen: Port 587 für STARTTLS '
                    'oder Port 465 für direkte SSL-Verbindung. '
                    'Die Vorgaben deines Providers sind maßgeblich.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white54,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _sending ? null : _saveSettings,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Einstellungen speichern'),
                    ),
                  ),
                ],
              ),
            ),

            _sectionTitle('Nachricht', Icons.edit_note),
            _panel(
              child: Column(
                children: [
                  _field(
                    'Betreff',
                    _subjectController,
                    hint: 'Dein Betreff',
                  ),
                  TextField(
                    controller: _messageController,
                    minLines: 7,
                    maxLines: 12,
                    decoration: const InputDecoration(
                      labelText: 'Nachricht',
                      hintText: 'Schreibe hier deine E-Mail ...',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Hinweis: Der Nachrichtentext wird als einfacher '
                    'Text versendet. HTML-Formatierung ist nicht aktiviert.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ),

            _sectionTitle('Versand', Icons.send_outlined),
            _panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _status,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: _sending ? _progress : null,
                    backgroundColor: const Color(0xFF302747),
                    color: const Color(0xFFB99BFF),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: _sending ? null : _sendEmails,
                      icon: Icon(
                        _sending ? Icons.hourglass_top : Icons.send,
                      ),
                      label: Text(
                        _sending ? 'Versand läuft ...' : 'E-Mails versenden',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Jede Nachricht wird einzeln versendet. '
                    'Der SMTP-Server kann Versandlimits oder Sperren '
                    'durchsetzen. Prüfe die Berechtigung der Empfänger '
                    'und beachte die geltenden Datenschutz- und '
                    'Werberegeln.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            const Center(
              child: Text(
                'PRADADEVS  •  Pradadevvs',
                style: TextStyle(
                  color: Color(0xFFB99BFF),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1729),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFFB99BFF), size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white60,
            ),
          ),
        ],
      ),
    );
  }
}

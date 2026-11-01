import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PRADA´DEVS Bulk Email',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101018),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF9B72FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1B1B27),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const BulkEmailPage(),
    );
  }
}

class BulkEmailPage extends StatefulWidget {
  const BulkEmailPage({super.key});

  @override
  State<BulkEmailPage> createState() => _BulkEmailPageState();
}

class _BulkEmailPageState extends State<BulkEmailPage> {
  static const _storage = FlutterSecureStorage();

  final _senderController = TextEditingController();
  final _passwordController = TextEditingController();
  final _recipientController = TextEditingController();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();

  final List<String> _recipients = [];

  String _provider = 'Gmail';
  bool _saving = false;
  bool _sending = false;
  bool _hidePassword = true;
  String _status = 'Noch nicht verbunden';

  String get _host => _provider == 'Outlook'
      ? 'smtp.office365.com'
      : _provider == 'Yahoo'
          ? 'smtp.mail.yahoo.com'
          : 'smtp.gmail.com';

  int get _port => 587;

  @override
  void initState() {
    super.initState();
    _loadSavedAccount();
  }

  Future<void> _loadSavedAccount() async {
    final email = await _storage.read(key: 'sender_email');
    final password = await _storage.read(key: 'smtp_password');
    final provider = await _storage.read(key: 'smtp_provider');

    if (!mounted) return;

    setState(() {
      _senderController.text = email ?? '';
      _passwordController.text = password ?? '';

      if (provider != null &&
          ['Gmail', 'Outlook', 'Yahoo'].contains(provider)) {
        _provider = provider;
      }

      if (email != null && password != null && password.isNotEmpty) {
        _status = 'Zugangsdaten lokal gespeichert';
      }
    });
  }

  @override
  void dispose() {
    _senderController.dispose();
    _passwordController.dispose();
    _recipientController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _addRecipient() {
    final email = _recipientController.text.trim();

    final valid =
        RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);

    if (!valid) {
      _showMessage('Bitte eine gültige E-Mail-Adresse eingeben.');
      return;
    }

    if (_recipients.any(
      (item) => item.toLowerCase() == email.toLowerCase(),
    )) {
      _showMessage('Diese Adresse ist bereits in der Liste.');
      return;
    }

    setState(() {
      _recipients.add(email);
      _recipientController.clear();
    });
  }

  Future<void> _saveAccount() async {
    final email = _senderController.text.trim();
    final password = _passwordController.text;

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email) ||
        password.isEmpty) {
      _showMessage(
        'Bitte Absender-E-Mail und SMTP-Passwort eingeben.',
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await _storage.write(key: 'sender_email', value: email);
      await _storage.write(key: 'smtp_password', value: password);
      await _storage.write(key: 'smtp_provider', value: _provider);

      if (!mounted) return;

      setState(() {
        _status = 'Zugangsdaten sicher auf diesem Gerät gespeichert';
      });

      _showMessage('Zugangsdaten wurden lokal gespeichert.');
    } catch (error) {
      _showMessage('Speichern fehlgeschlagen: $error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _sendEmails() async {
    final sender = _senderController.text.trim();
    final password = _passwordController.text;
    final subject = _subjectController.text.trim();
    final body = _messageController.text.trim();

    if (_recipients.isEmpty) {
      _showMessage(
        'Bitte zuerst mindestens einen Empfänger hinzufügen.',
      );
      return;
    }

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(sender) ||
        password.isEmpty) {
      _showMessage(
        'Bitte zuerst gültige SMTP-Zugangsdaten eintragen.',
      );
      return;
    }

    if (subject.isEmpty || body.isEmpty) {
      _showMessage('Bitte Betreff und Nachricht ausfüllen.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('E-Mails wirklich versenden?'),
        content: Text(
          'Es werden ${_recipients.length} einzelne E-Mail(s) '
          'über $_provider versendet. Bitte stelle sicher, dass '
          'alle Empfänger dem Erhalt zugestimmt haben.',
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

    setState(() {
      _sending = true;
      _status = 'Versand läuft ...';
    });

    try {
      final server = SmtpServer(
        _host,
        port: _port,
        username: sender,
        password: password,
        ssl: false,
      );

      var sent = 0;
      final failed = <String>[];

      for (final recipient in List<String>.from(_recipients)) {
        final email = Message()
          ..from = Address(sender)
          ..recipients.add(recipient)
          ..subject = subject
          ..text = body;

        try {
          await send(email, server);
          sent++;
        } catch (_) {
          failed.add(recipient);
        }
      }

      if (!mounted) return;

      setState(() {
        _status =
            'Fertig: $sent gesendet, ${failed.length} fehlgeschlagen';
      });

      if (failed.isEmpty) {
        _showMessage(
          '$sent E-Mail(s) erfolgreich an den SMTP-Server übergeben.',
        );
      } else {
        _showMessage(
          '$sent gesendet, ${failed.length} fehlgeschlagen:\n'
          '${failed.join('\n')}',
        );
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _status = 'Versand fehlgeschlagen';
      });

      _showMessage('SMTP-Verbindung fehlgeschlagen: $error');
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _clearSavedAccount() async {
    await _storage.delete(key: 'sender_email');
    await _storage.delete(key: 'smtp_password');
    await _storage.delete(key: 'smtp_provider');

    if (!mounted) return;

    setState(() {
      _senderController.clear();
      _passwordController.clear();
      _status = 'Zugangsdaten gelöscht';
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message)),
      );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 22),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFB99AFF)),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int lines = 1,
    TextInputType keyboardType = TextInputType.text,
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      maxLines: obscure ? 1 : lines,
      keyboardType: keyboardType,
      obscureText: obscure && _hidePassword,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: obscure
            ? IconButton(
                onPressed: () {
                  setState(() {
                    _hidePassword = !_hidePassword;
                  });
                },
                icon: Icon(
                  _hidePassword
                      ? Icons.visibility
                      : Icons.visibility_off,
                ),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'PRADA´DEVS',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Zugangsdaten löschen',
            onPressed: _clearSavedAccount,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF30234E),
                    Color(0xFF191925),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BULK EMAIL',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Empfänger verwalten und E-Mails direkt '
                    'per SMTP versenden.',
                  ),
                ],
              ),
            ),

            _sectionTitle('1. E-Mail-Konto', Icons.mail_outline),

            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF171722),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButton<String>(
                    value: _provider,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: 'Gmail',
                        child: Text('Gmail'),
                      ),
                      DropdownMenuItem(
                        value: 'Outlook',
                        child: Text('Outlook'),
                      ),
                      DropdownMenuItem(
                        value: 'Yahoo',
                        child: Text('Yahoo'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _provider = value);
                      }
                    },
                  ),

                  const SizedBox(height: 10),

                  _field(
                    _senderController,
                    'Deine Absender-E-Mail',
                    keyboardType: TextInputType.emailAddress,
                  ),

                  const SizedBox(height: 10),

                  _field(
                    _passwordController,
                    'SMTP-Passwort / App-Passwort',
                    obscure: true,
                  ),

                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _saveAccount,
                      icon: const Icon(Icons.lock_outline),
                      label: Text(
                        _saving
                            ? 'Speichert ...'
                            : 'Zugangsdaten sicher speichern',
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Server: $_host · Port: $_port (STARTTLS)',
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            _sectionTitle('2. Empfänger', Icons.people_outline),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _recipientController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'E-Mail-Adresse',
                      hintText: 'name@beispiel.de',
                    ),
                    onSubmitted: (_) => _addRecipient(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _addRecipient,
                  icon: const Icon(Icons.add),
                  tooltip: 'Empfänger hinzufügen',
                ),
              ],
            ),

            const SizedBox(height: 10),

            if (_recipients.isEmpty)
              const Text(
                'Noch keine Empfänger hinzugefügt.',
                style: TextStyle(color: Colors.white60),
              )
            else
              ..._recipients.asMap().entries.map(
                (entry) => Card(
                  color: const Color(0xFF1B1B27),
                  child: ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF392A5A),
                      child: Text('${entry.key + 1}'),
                    ),
                    title: Text(entry.value),
                    trailing: IconButton(
                      tooltip: 'Entfernen',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        setState(() {
                          _recipients.remove(entry.value);
                        });
                      },
                    ),
                  ),
                ),
              ),

            _sectionTitle('3. Nachricht', Icons.edit_note),

            _field(_subjectController, 'Betreff'),

            const SizedBox(height: 10),

            _field(
              _messageController,
              'Nachricht',
              lines: 7,
            ),

            const SizedBox(height: 20),

            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: _sending ? null : _sendEmails,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.send),
                label: Text(
                  _sending
                      ? 'Versand läuft ...'
                      : 'E-Mails versenden (${_recipients.length})',
                ),
              ),
            ),

            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1B1B27),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Color(0xFFB99AFF),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_status),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            Text(
              'Hinweis: SMTP-Zugangsdaten werden verschlüsselt '
              'auf diesem Gerät gespeichert. Für Gmail ist '
              'normalerweise ein App-Passwort erforderlich. '
              'Versende nur an Empfänger, die dem Erhalt '
              'zugestimmt haben, und beachte Versandlimits.',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

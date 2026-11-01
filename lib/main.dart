import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

void main() => runApp(const PradaDevsApp());

class PradaDevsApp extends StatelessWidget {
  const PradaDevsApp({super.key});

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF080B14);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PRADA´DEVS Bulk Email',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8B7CFF),
          brightness: Brightness.dark,
          surface: const Color(0xFF121827),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0C1220),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF29344B)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF29344B)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF9C8CFF), width: 1.5),
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const purple = Color(0xFF9C8CFF);
  static const cyan = Color(0xFF53D8E8);
  final emailController = TextEditingController();
  final subjectController = TextEditingController();
  final messageController = TextEditingController();
  final List<String> contacts = [];
  static const secureStore = FlutterSecureStorage();
  final smtpHostController = TextEditingController();
  final smtpPortController = TextEditingController(text: '587');
  final smtpUserController = TextEditingController();
  final smtpPasswordController = TextEditingController();
  final senderEmailController = TextEditingController();
  bool smtpSsl = false;
  bool sending = false;
  String provider = 'Gmail';
  bool importing = false;
  String status = 'Deine Kontakte sind bereit.';
  int rejected = 0;

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _loadSmtpSettings();
  }

  @override
  void dispose() {
    emailController.dispose();
    subjectController.dispose();
    messageController.dispose();
    smtpHostController.dispose();
    smtpPortController.dispose();
    smtpUserController.dispose();
    smtpPasswordController.dispose();
    senderEmailController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('contacts_v2') ?? [];
    if (!mounted) return;
    setState(() {
      contacts
        ..clear()
        ..addAll(saved);
    });
  }

  Future<void> _loadSmtpSettings() async {
    final prefs = await SharedPreferences.getInstance();
    smtpHostController.text = prefs.getString('smtp_host') ?? '';
    smtpPortController.text = prefs.getString('smtp_port') ?? '587';
    smtpUserController.text = prefs.getString('smtp_user') ?? '';
    senderEmailController.text = prefs.getString('smtp_sender') ?? '';
    smtpSsl = prefs.getBool('smtp_ssl') ?? false;
    smtpPasswordController.text = await secureStore.read(key: 'smtp_password') ?? '';
    if (mounted) setState(() {});
  }

  Future<void> _saveSmtpSettings() async {
    final host = smtpHostController.text.trim();
    final port = int.tryParse(smtpPortController.text.trim());
    if (host.isEmpty || port == null || port < 1 || port > 65535 ||
        smtpUserController.text.trim().isEmpty ||
        smtpPasswordController.text.isEmpty ||
        !_validEmail(senderEmailController.text)) {
      _notify('Bitte Host, gültigen Port, Benutzername, Passwort und Absenderadresse prüfen.');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('smtp_host', host);
    await prefs.setString('smtp_port', port.toString());
    await prefs.setString('smtp_user', smtpUserController.text.trim());
    await prefs.setString('smtp_sender', senderEmailController.text.trim());
    await prefs.setBool('smtp_ssl', smtpSsl);
    await secureStore.write(key: 'smtp_password', value: smtpPasswordController.text);
    _notify('SMTP-Einstellungen sicher auf dem Gerät gespeichert.');
  }

  SmtpServer _smtpServer() {
    final port = int.parse(smtpPortController.text.trim());
    return SmtpServer(
      smtpHostController.text.trim(),
      port: port,
      username: smtpUserController.text.trim(),
      password: smtpPasswordController.text,
      ssl: smtpSsl,
      allowInsecure: false,
    );
  }

  Future<void> _testSmtp() async {
    await _saveSmtpSettings();
    if (!mounted) return;
    if (smtpHostController.text.trim().isEmpty || smtpPasswordController.text.isEmpty) return;
    setState(() => sending = true);
    try {
      final message = Message()
        ..from = Address(senderEmailController.text.trim())
        ..recipients.add(senderEmailController.text.trim())
        ..subject = 'PRADA´DEVS SMTP Verbindungstest'
        ..text = 'Der SMTP-Verbindungstest war erfolgreich.';
      await send(message, _smtpServer()).timeout(const Duration(seconds: 25));
      _notify('SMTP-Testmail wurde angenommen. Bitte Posteingang prüfen.');
    } catch (e) {
      _notify('SMTP-Test fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _sendCampaign() async {
    if (contacts.isEmpty) {
      _notify('Bitte zuerst Kontakte importieren oder hinzufügen.');
      return;
    }
    if (subjectController.text.trim().isEmpty || messageController.text.trim().isEmpty) {
      _notify('Bitte Betreff und Nachricht ausfüllen.');
      return;
    }
    if (smtpHostController.text.trim().isEmpty || smtpPasswordController.text.isEmpty ||
        !_validEmail(senderEmailController.text)) {
      _notify('Bitte zuerst deine SMTP-Einstellungen vollständig eintragen.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Versand bestätigen'),
        content: Text('Es werden ${contacts.length} E-Mails einzeln versendet. Nur Empfänger kontaktieren, die dem Erhalt zugestimmt haben.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Versand starten')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => sending = true);
    int sent = 0;
    int failed = 0;
    try {
      final server = _smtpServer();
      for (final recipient in List<String>.from(contacts)) {
        try {
          final message = Message()
            ..from = Address(senderEmailController.text.trim())
            ..recipients.add(recipient)
            ..subject = subjectController.text.trim()
            ..text = messageController.text;
          await send(message, server).timeout(const Duration(seconds: 30));
          sent++;
        } catch (_) {
          failed++;
        }
        if (mounted) {
          setState(() => status = 'Versand läuft: $sent erfolgreich · $failed fehlgeschlagen');
        }
      }
      _notify('Versand abgeschlossen: $sent erfolgreich, $failed fehlgeschlagen.');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _saveContacts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('contacts_v2', contacts);
  }

  bool _validEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());
  }

  Future<void> _addManual() async {
    final value = emailController.text.trim().toLowerCase();
    if (!_validEmail(value)) {
      _notify('Bitte gib eine gültige E-Mail-Adresse ein.');
      return;
    }
    if (contacts.contains(value)) {
      _notify('Diese Adresse ist bereits in deiner Liste.');
      return;
    }
    setState(() {
      contacts.add(value);
      emailController.clear();
      status = '1 Kontakt hinzugefügt.';
    });
    await _saveContacts();
  }

  String _findEmailInRow(List<dynamic> row) {
    for (final cell in row) {
      final value = cell?.toString().trim().toLowerCase() ?? '';
      if (_validEmail(value)) return value;
    }
    return '';
  }

  Future<void> _importFile() async {
    setState(() => importing = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'csv'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final Uint8List? bytes = file.bytes;
      if (bytes == null) {
        _notify('Die Datei konnte nicht gelesen werden.');
        return;
      }

      final extension = (file.extension ?? '').toLowerCase();
      final Set<String> found = {};
      if (extension == 'xlsx') {
        final workbook = Excel.decodeBytes(bytes);
        for (final sheetName in workbook.tables.keys) {
          final sheet = workbook.tables[sheetName];
          if (sheet == null) continue;
          for (final row in sheet.rows) {
            final email = _findEmailInRow(row.map((cell) => cell?.value).toList());
            if (email.isNotEmpty) found.add(email);
          }
        }
      } else if (extension == 'csv') {
        final content = utf8.decode(bytes, allowMalformed: true);
        final rows = const CsvToListConverter(
          shouldParseNumbers: false,
          allowInvalid: true,
        ).convert(content);
        for (final row in rows) {
          final email = _findEmailInRow(row);
          if (email.isNotEmpty) found.add(email);
        }
      }

      final before = contacts.length;
      int added = 0;
      for (final email in found) {
        if (!contacts.contains(email)) {
          contacts.add(email);
          added++;
        }
      }
      rejected = found.length - added;
      await _saveContacts();
      if (!mounted) return;
      setState(() {
        status = '$added neue Kontakte importiert · $rejected bereits vorhanden.';
      });
      _notify('$added neue Adressen importiert. ${contacts.length - before} Kontakte insgesamt neu hinzugefügt.');
    } catch (e) {
      _notify('Import fehlgeschlagen. Bitte prüfe die Datei: $e');
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Future<void> _removeContact(String email) async {
    setState(() => contacts.remove(email));
    await _saveContacts();
    _notify('Kontakt entfernt.');
  }

  void _notify(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }

  Future<void> _openTelegram() async {
    final uri = Uri.parse('https://t.me/Pradadevvs');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _notify('Telegram-Link konnte nicht geöffnet werden.');
    }
  }

  Widget _panel({required Widget child, EdgeInsets padding = const EdgeInsets.all(18)}) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF121827),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF27334B)),
        boxShadow: const [
          BoxShadow(color: Color(0x18000000), blurRadius: 18, offset: Offset(0, 8)),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String number, String title, String subtitle) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: purple.withOpacity(.16),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: purple.withOpacity(.4)),
          ),
          child: Text(number, style: const TextStyle(color: purple, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: Color(0xFF9BA8BE), fontSize: 12)),
          ]),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
              sliver: SliverList.list(children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [purple, cyan]),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(Icons.bolt_rounded, color: Color(0xFF08101B), size: 29),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('PRADA´DEVS', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
                        Text('BULK EMAIL STUDIO', style: TextStyle(fontSize: 10, color: cyan, letterSpacing: 2.0, fontWeight: FontWeight.w700)),
                      ],
                    )),
                    IconButton(
                      onPressed: _openTelegram,
                      tooltip: 'Telegram @Pradadevvs',
                      icon: const Icon(Icons.send_rounded, color: cyan),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF29264F), Color(0xFF142B3D), Color(0xFF111827)],
                    ),
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(color: purple.withOpacity(.35)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('DEINE KAMPAGNE.', style: TextStyle(color: cyan, fontSize: 11, letterSpacing: 2.2, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 9),
                    const Text('Kontakte. Klarheit.\nMehr Überblick.', style: TextStyle(fontSize: 27, height: 1.12, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 12),
                    const Text('Verwalte deine Empfängerliste und bereite Nachrichten an einem Ort vor.', style: TextStyle(color: Color(0xFFC0C9D8), height: 1.4)),
                    const SizedBox(height: 18),
                    Row(children: [
                      _stat('${contacts.length}', 'KONTAKTE'),
                      const SizedBox(width: 10),
                      _stat('XLSX', 'EXCEL-IMPORT'),
                      const SizedBox(width: 10),
                      _stat('CSV', 'DATEI-IMPORT'),
                    ]),
                  ]),
                ),
                const SizedBox(height: 22),
                _panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _sectionTitle('01', 'Versandanbieter', 'Anbieter für deine spätere Versand-Anbindung'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: provider,
                    decoration: const InputDecoration(labelText: 'Ausgewählter Anbieter', prefixIcon: Icon(Icons.alternate_email_rounded)),
                    items: const ['Gmail', 'Outlook', 'SMTP'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                    onChanged: (v) => setState(() => provider = v ?? 'Gmail'),
                  ),
                  const SizedBox(height: 9),
                  const Text('Die sichere Kontoverbindung und der echte Versand werden in einem separaten Schritt ergänzt.', style: TextStyle(color: Color(0xFF9BA8BE), fontSize: 12, height: 1.4)),
                ])),
                const SizedBox(height: 14),
                _panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _sectionTitle('02', 'Kontaktzentrale', 'Einzeln hinzufügen oder ganze Listen importieren'),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(hintText: 'name@beispiel.de', prefixIcon: Icon(Icons.mail_outline_rounded)),
                      onSubmitted: (_) => _addManual(),
                    )),
                    const SizedBox(width: 9),
                    SizedBox(height: 54, child: FilledButton(
                      onPressed: _addManual,
                      style: FilledButton.styleFrom(backgroundColor: purple, foregroundColor: const Color(0xFF101322), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                      child: const Icon(Icons.add_rounded),
                    )),
                  ]),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: importing ? null : _importFile,
                      icon: importing
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.file_upload_outlined),
                      label: Text(importing ? 'DATEI WIRD EINGELESEN…' : 'EXCEL / CSV IMPORTIEREN'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cyan,
                        side: BorderSide(color: cyan.withOpacity(.65)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('Unterstützt .xlsx und .csv. Die App sucht gültige E-Mail-Adressen in allen Spalten und überspringt Duplikate.', style: TextStyle(color: Color(0xFF9BA8BE), fontSize: 12, height: 1.45)),
                  const SizedBox(height: 15),
                  Row(children: [
                    const Expanded(child: Text('DEINE EMPFÄNGER', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1))),
                    Text('${contacts.length} gespeichert', style: const TextStyle(color: cyan, fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 8),
                  if (contacts.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 23, horizontal: 12),
                      decoration: BoxDecoration(color: const Color(0xFF0C1220), borderRadius: BorderRadius.circular(15)),
                      child: const Column(children: [
                        Icon(Icons.contact_mail_outlined, color: Color(0xFF65738C), size: 30),
                        SizedBox(height: 8),
                        Text('Noch keine Kontakte', style: TextStyle(fontWeight: FontWeight.w700)),
                        SizedBox(height: 3),
                        Text('Importiere deine Excel-Liste oder füge Adressen einzeln hinzu.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF9BA8BE), fontSize: 12)),
                      ]),
                    )
                  else
                    ...contacts.asMap().entries.map((entry) => Container(
                      margin: const EdgeInsets.only(top: 7),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: const Color(0xFF0C1220), borderRadius: BorderRadius.circular(13)),
                      child: Row(children: [
                        const Icon(Icons.check_circle_rounded, color: cyan, size: 18),
                        const SizedBox(width: 9),
                        Expanded(child: Text(entry.value, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _removeContact(entry.value),
                          icon: const Icon(Icons.close_rounded, color: Color(0xFF9BA8BE), size: 19),
                        ),
                      ]),
                    )),
                  const SizedBox(height: 10),
                  Text(status, style: const TextStyle(color: Color(0xFF9BA8BE), fontSize: 11)),
                ])),
                const SizedBox(height: 14),
                _panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _sectionTitle('03', 'Nachricht vorbereiten', 'Betreff und Nachricht für deine Kampagne'),
                  const SizedBox(height: 16),
                  TextField(controller: subjectController, decoration: const InputDecoration(labelText: 'Betreff', prefixIcon: Icon(Icons.title_rounded))),
                  const SizedBox(height: 12),
                  TextField(
                    controller: messageController,
                    minLines: 5,
                    maxLines: 8,
                    decoration: const InputDecoration(labelText: 'Deine Nachricht', alignLabelWithHint: true, prefixIcon: Icon(Icons.edit_note_rounded)),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFF302A19).withOpacity(.5), borderRadius: BorderRadius.circular(13), border: Border.all(color: const Color(0xFF8E7130).withOpacity(.5))),
                    child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.info_outline_rounded, color: Color(0xFFE8C36A), size: 18),
                      SizedBox(width: 9),
                      Expanded(child: Text('Der Versand ist noch nicht aktiviert. Verwende Empfängerlisten nur mit entsprechender Einwilligung und beachte Abmeldemöglichkeiten.', style: TextStyle(color: Color(0xFFE4D6AE), fontSize: 11, height: 1.4))),
                    ]),
                  ),
                  const SizedBox(height: 13),
                  SizedBox(width: double.infinity, child: FilledButton.icon(
                    onPressed: sending ? null : _sendCampaign,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(sending ? 'VERSAND LÄUFT…' : 'KAMPAGNE VERSENDEN'),
                    style: FilledButton.styleFrom(backgroundColor: purple, foregroundColor: const Color(0xFF101322), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                  )),
                ])),
                const SizedBox(height: 18),
                InkWell(
                  onTap: _openTelegram,
                  borderRadius: BorderRadius.circular(18),
                  child: _panel(child: const Row(children: [
                    Icon(Icons.send_rounded, color: cyan, size: 26),
                    SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('CONNECT WITH PRADA´DEVS', style: TextStyle(fontSize: 11, color: cyan, letterSpacing: 1.3, fontWeight: FontWeight.w800)),
                      SizedBox(height: 4),
                      Text('@Pradadevvs', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    ])),
                    Icon(Icons.open_in_new_rounded, color: Color(0xFF9BA8BE)),
                  ])),
                ),
                const SizedBox(height: 18),
                const Center(child: Text('PRADA´DEVS  •  BULK EMAIL STUDIO  •  V 0.2.0', style: TextStyle(color: Color(0xFF65738C), fontSize: 9, letterSpacing: 1.1))),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(color: const Color(0x220A0E1B), borderRadius: BorderRadius.circular(13), border: Border.all(color: const Color(0x337F8CFF))),
      child: Column(children: [
        Text(value, style: const TextStyle(color: cyan, fontSize: 15, fontWeight: FontWeight.w900)),
        const SizedBox(height: 3),
        Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFB6C0D2), fontSize: 8, letterSpacing: .7)),
      ]),
    ));
  }
}

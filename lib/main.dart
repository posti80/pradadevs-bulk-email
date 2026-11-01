import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PradaDevsApp());
}

class PradaDevsApp extends StatelessWidget {
  const PradaDevsApp({super.key});

  @override
  Widget build(BuildContext context) {
    const violet = Color(0xFF9B72FF);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PRADA´DEVS Bulk Email',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101018),
        colorScheme: ColorScheme.fromSeed(
          seedColor: violet,
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF171722),
          foregroundColor: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF20202D),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        useMaterial3: true,
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
  final List<String> recipients = [];

  final TextEditingController emailController =
      TextEditingController();

  final TextEditingController subjectController =
      TextEditingController();

  final TextEditingController messageController =
      TextEditingController();

  bool loading = false;

  static const String storageKey = 'pradadevs_recipients';

  @override
  void initState() {
    super.initState();
    loadRecipients();
  }

  @override
  void dispose() {
    emailController.dispose();
    subjectController.dispose();
    messageController.dispose();
    super.dispose();
  }

  bool isValidEmail(String email) {
    return RegExp(
      r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
    ).hasMatch(email.trim());
  }

  Future<void> loadRecipients() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(storageKey) ?? [];

    if (!mounted) return;

    setState(() {
      recipients
        ..clear()
        ..addAll(saved);
    });
  }

  Future<void> saveRecipients() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(storageKey, recipients);
  }

  void showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> addRecipient() async {
    emailController.clear();

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Empfänger hinzufügen'),
          content: TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'E-Mail-Adresse',
              hintText: 'name@beispiel.de',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  emailController.text.trim(),
                );
              },
              child: const Text('Hinzufügen'),
            ),
          ],
        );
      },
    );

    if (result == null || result.isEmpty) return;

    final email = result.toLowerCase();

    if (!isValidEmail(email)) {
      showMessage('Bitte eine gültige E-Mail-Adresse eingeben.');
      return;
    }

    if (recipients.contains(email)) {
      showMessage('Diese Adresse ist bereits vorhanden.');
      return;
    }

    setState(() {
      recipients.add(email);
    });

    await saveRecipients();
    showMessage('Empfänger hinzugefügt.');
  }

  Future<void> removeRecipient(String email) async {
    setState(() {
      recipients.remove(email);
    });

    await saveRecipients();
  }

  Future<void> importFile() async {
    try {
      setState(() => loading = true);

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.first;
      final bytes = file.bytes;

      if (bytes == null) {
        showMessage('Die Datei konnte nicht gelesen werden.');
        return;
      }

      final extension = file.extension?.toLowerCase();
      final Set<String> importedEmails = {};

      if (extension == 'csv') {
        final content = utf8.decode(
          bytes,
          allowMalformed: true,
        );

        final rows = const CsvToListConverter(
          shouldParseNumbers: false,
        ).convert(content);

        for (final row in rows) {
          for (final cell in row) {
            final value = cell.toString().trim().toLowerCase();

            if (isValidEmail(value)) {
              importedEmails.add(value);
            }
          }
        }
      } else if (extension == 'xlsx') {
        final workbook = xls.Excel.decodeBytes(bytes);

        for (final sheet in workbook.tables.values) {
          for (final row in sheet.rows) {
            for (final cell in row) {
              final value =
                  cell?.value?.toString().trim().toLowerCase() ?? '';

              if (isValidEmail(value)) {
                importedEmails.add(value);
              }
            }
          }
        }
      } else {
        showMessage('Dieses Dateiformat wird nicht unterstützt.');
        return;
      }

      final before = recipients.length;

      setState(() {
        recipients.addAll(
          importedEmails.where(
            (email) => !recipients.contains(email),
          ),
        );
      });

      await saveRecipients();

      final added = recipients.length - before;

      showMessage(
        '$added neue Empfänger importiert.',
      );
    } catch (error) {
      showMessage('Import fehlgeschlagen: $error');
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> copyRecipients() async {
    if (recipients.isEmpty) {
      showMessage('Es sind noch keine Empfänger vorhanden.');
      return;
    }

    await Clipboard.setData(
      ClipboardData(text: recipients.join('; ')),
    );

    showMessage('Empfängerliste wurde kopiert.');
  }

  Future<void> prepareEmail() async {
    if (recipients.isEmpty) {
      showMessage('Bitte zuerst Empfänger hinzufügen.');
      return;
    }

    if (subjectController.text.trim().isEmpty) {
      showMessage('Bitte einen Betreff eingeben.');
      return;
    }

    if (messageController.text.trim().isEmpty) {
      showMessage('Bitte eine Nachricht eingeben.');
      return;
    }

    final subject = subjectController.text.trim();
    final message = messageController.text.trim();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Versand vorbereitet'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Empfänger: ${recipients.length}'),
                const SizedBox(height: 12),
                const Text(
                  'Betreff',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(subject),
                const SizedBox(height: 12),
                const Text(
                  'Nachricht',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(message),
                const SizedBox(height: 12),
                const Text(
                  'Die Nachricht wurde vorbereitet. '
                  'Ein automatischer E-Mail-Versand ist '
                  'noch nicht eingerichtet.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Schließen'),
            ),
            FilledButton(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(
                    text: 'Betreff: $subject\n\n$message',
                  ),
                );

                if (context.mounted) {
                  Navigator.pop(context);
                }

                showMessage('Nachricht wurde kopiert.');
              },
              child: const Text('Nachricht kopieren'),
            ),
          ],
        );
      },
    );
  }

  Widget sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 20),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'PRADA´DEVS',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: loadRecipients,
            icon: const Icon(Icons.refresh),
            tooltip: 'Aktualisieren',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF5736A8),
                    Color(0xFF292044),
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.mark_email_read_outlined,
                    size: 38,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Bulk Email Manager',
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Deine Empfänger. Deine Nachrichten. '
                    'Alles an einem Ort.',
                  ),
                ],
              ),
            ),

            sectionTitle('Empfänger'),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Text(
                      '${recipients.length}',
                      style: const TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFB18AFF),
                      ),
                    ),
                    const Text('Gespeicherte E-Mail-Adressen'),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: addRecipient,
                            icon: const Icon(Icons.person_add),
                            label: const Text('Hinzufügen'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: loading ? null : importFile,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('CSV / Excel importieren'),
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: copyRecipients,
                        icon: const Icon(Icons.copy),
                        label: const Text('Adressen kopieren'),
                      ),
                    ),
                    if (loading) ...[
                      const SizedBox(height: 12),
                      const CircularProgressIndicator(),
                    ],
                  ],
                ),
              ),
            ),

            sectionTitle('Empfängerliste'),

            if (recipients.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Noch keine Empfänger vorhanden. '
                    'Füge eine Adresse hinzu oder importiere eine Datei.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              ...recipients.map(
                (email) => Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.email_outlined),
                    ),
                    title: Text(email),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                      ),
                      onPressed: () => removeRecipient(email),
                    ),
                  ),
                ),
              ),

            sectionTitle('E-Mail erstellen'),

            TextField(
              controller: subjectController,
              decoration: const InputDecoration(
                labelText: 'Betreff',
                prefixIcon: Icon(Icons.title),
              ),
            ),

            const SizedBox(height: 14),

            TextField(
              controller: messageController,
              minLines: 6,
              maxLines: 10,
              decoration: const InputDecoration(
                labelText: 'Nachricht',
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.message_outlined),
                hintText: 'Schreibe hier deine Nachricht ...',
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: prepareEmail,
                icon: const Icon(Icons.send),
                label: const Text(
                  'VERSAND VORBEREITEN',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              'PRADA´DEVS • Bulk Email Manager',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

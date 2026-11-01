import 'package:flutter/material.dart';

void main() => runApp(const PradaBulkEmailApp());

class PradaBulkEmailApp extends StatelessWidget {
  const PradaBulkEmailApp({super.key});

  @override
  Widget build(BuildContext context) {
    const violet = Color(0xFF8B6CFF);

    return MaterialApp(
      title: 'PRADA´DEVS Bulk Email',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: violet,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF10111A),
        useMaterial3: true,
      ),
      home: const DashboardPage(),
    );
  }
}

class Contact {
  Contact(this.email);
  final String email;
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final emailController = TextEditingController();
  final subjectController = TextEditingController();
  final messageController = TextEditingController();

  final List<Contact> contacts = [];

  String provider = 'Gmail';
  String status = 'Entwurf – noch nicht versendet';

  @override
  void dispose() {
    emailController.dispose();
    subjectController.dispose();
    messageController.dispose();
    super.dispose();
  }

  void addContact() {
    final email = emailController.text.trim();

    final valid = RegExp(
      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
    ).hasMatch(email);

    if (!valid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte eine gültige E-Mail-Adresse eingeben.'),
        ),
      );
      return;
    }

    if (contacts.any(
      (c) => c.email.toLowerCase() == email.toLowerCase(),
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Diese Adresse ist bereits vorhanden.'),
        ),
      );
      return;
    }

    setState(() {
      contacts.add(Contact(email));
      emailController.clear();
    });
  }

  void showSendNotice() {
    setState(() {
      status = 'Bereit zur Anbindung – Versand noch deaktiviert.';
    });

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Versand noch nicht verbunden'),
        content: const Text(
          'Gmail, Outlook und SMTP benötigen eine sichere '
          'Anbindung. Diese erste Version bereitet Kontakte '
          'und Nachrichten vor, versendet aber noch keine E-Mails.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Verstanden'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PRADA´DEVS'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(
              child: Text('BULK EMAIL'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'E-Mail Kampagne',
            style: TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Kontakte verwalten und Nachrichten vorbereiten',
          ),
          const SizedBox(height: 20),

          // Anbieter
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Versandanbieter',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: provider,
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
                        value: 'Eigener SMTP',
                        child: Text('Eigener SMTP'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        provider = value ?? 'Gmail';
                      });
                    },
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Die sichere Kontoanbindung folgt in einer späteren Version.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Kontakte
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Kontakte',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'E-Mail-Adresse',
                            hintText: 'name@beispiel.de',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => addContact(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: addContact,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${contacts.length} Kontakte hinzugefügt',
                  ),
                  if (contacts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        'Noch keine Kontakte vorhanden.',
                      ),
                    ),
                  ...contacts.asMap().entries.map(
                    (entry) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.email_outlined),
                      title: Text(entry.value.email),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          setState(() {
                            contacts.removeAt(entry.key);
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Nachricht
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nachricht vorbereiten',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: subjectController,
                    decoration: const InputDecoration(
                      labelText: 'Betreff',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: messageController,
                    minLines: 5,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: 'Nachricht',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: showSendNotice,
                      icon: const Icon(Icons.send_outlined),
                      label: const Text('Versand vorbereiten'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Kampagnenstatus'),
            subtitle: Text(status),
          ),

          const Padding(
            padding: EdgeInsets.only(top: 8, bottom: 20),
            child: Text(
              'Bitte nur Empfänger anschreiben, die dem Erhalt '
              'zugestimmt haben. Eine Abmeldemöglichkeit muss '
              'vor echtem Kampagnenversand vorhanden sein.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

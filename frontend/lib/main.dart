import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

const ink = Color(0xFF142436);
const canvas = Color(0xFFF3F6FA);
const blue = Color(0xFF1769E0);
const muted = Color(0xFF68788A);

void main() {
  runApp(const CivicPulseApp());
}

class CivicPulseApp extends StatelessWidget {
  const CivicPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CivicPulse AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: canvas,
        colorScheme: ColorScheme.fromSeed(seedColor: blue),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: ink,
          elevation: 0,
          centerTitle: false,
        ),
      ),
      home: const CivicPulseHome(),
    );
  }
}

class CivicPulseHome extends StatefulWidget {
  const CivicPulseHome({super.key});

  @override
  State<CivicPulseHome> createState() => _CivicPulseHomeState();
}

class _CivicPulseHomeState extends State<CivicPulseHome> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [const CitizenReportPage(), const GovernmentDashboardPage()];
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.track_changes_rounded, color: Color(0xFFE83F76)),
            SizedBox(width: 9),
            Text('CIVICPULSE', style: TextStyle(fontWeight: FontWeight.w800)),
            SizedBox(width: 7),
            Text(
              'AI',
              style: TextStyle(color: blue, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Chip(
              avatar: const Icon(Icons.public, size: 17),
              label: Text(selectedIndex == 0 ? 'Citizen App' : 'Admin'),
              visualDensity: VisualDensity.compact,
              backgroundColor: const Color(0xFFF0F5FB),
              side: BorderSide.none,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(index: selectedIndex, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => setState(() => selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.record_voice_over_outlined),
            selectedIcon: Icon(Icons.record_voice_over),
            label: 'Citizen report',
          ),
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Government',
          ),
        ],
      ),
    );
  }
}

class CitizenReportPage extends StatefulWidget {
  const CitizenReportPage({super.key});

  @override
  State<CitizenReportPage> createState() => _CitizenReportPageState();
}

class _CitizenReportPageState extends State<CitizenReportPage> {
  final controller = TextEditingController();
  final speech = SpeechToText();
  String selectedLanguage = 'Auto-detect';
  String selectedCountry = 'India';
  String selectedLocation = 'Guntur';
  List<Map<String, dynamic>> countryOptions = [];
  bool submitting = false;
  bool listening = false;
  String? error;
  Map<String, dynamic>? result;
  String voicePrefix = '';

  @override
  void initState() {
    super.initState();
    loadCountryOptions();
  }

  Future<void> loadCountryOptions() async {
    try {
      final response = await http
          .get(Uri.parse('$apiBaseUrl/api/countries'))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Countries API returned ${response.statusCode}.');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List<dynamic>) {
        throw const FormatException('Unexpected countries response.');
      }
      if (!mounted) return;
      setState(() {
        countryOptions = decoded.cast<Map<String, dynamic>>();
        final current = countryOptions.where(
          (option) => option['name'] == selectedCountry,
        );
        if (current.isEmpty && countryOptions.isNotEmpty) {
          selectedCountry = countryOptions.first['name'].toString();
          selectedLocation = (countryOptions.first['regions'] as List<dynamic>)
              .first
              .toString();
        }
      });
    } catch (exception) {
      if (mounted) {
        setState(() {
          error = 'Could not load country and region options. $exception';
        });
      }
    }
  }

  Map<String, dynamic>? get selectedCountryOption {
    for (final option in countryOptions) {
      if (option['name'] == selectedCountry) return option;
    }
    return null;
  }

  List<String> get selectedLanguages =>
      (selectedCountryOption?['languages'] as List<dynamic>?)?.cast<String>() ??
      const ['English', 'Hindi', 'Telugu', 'Tamil', 'Kannada', 'Bengali'];

  List<String> get selectedRegions =>
      (selectedCountryOption?['regions'] as List<dynamic>?)?.cast<String>() ??
      const ['Guntur', 'Krishna'];

  @override
  void dispose() {
    speech.stop();
    controller.dispose();
    super.dispose();
  }

  Future<void> toggleVoiceInput() async {
    if (listening) {
      await speech.stop();
      return;
    }
    setState(() => error = null);
    try {
      final available = await speech.initialize(
        onStatus: (status) {
          if (mounted) setState(() => listening = status == 'listening');
        },
        onError: (speechError) {
          if (mounted) {
            setState(() {
              listening = false;
              error = 'Speech recognition error: ${speechError.errorMsg}';
            });
          }
        },
      );
      if (!available) {
        throw Exception(
          'Speech recognition is unavailable. Allow microphone access and try a supported browser or device.',
        );
      }
      voicePrefix = controller.text.trim();
      if (voicePrefix.isNotEmpty) voicePrefix = '$voicePrefix ';
      await speech.listen(
        onResult: (result) {
          if (!mounted || result.recognizedWords.isEmpty) return;
          final text = '$voicePrefix${result.recognizedWords}';
          controller.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          );
        },
        listenOptions: SpeechListenOptions(
          localeId: _speechLocale(selectedLanguage),
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: true,
          listenFor: const Duration(seconds: 45),
          pauseFor: const Duration(seconds: 4),
        ),
      );
      if (mounted) setState(() => listening = true);
    } catch (exception) {
      if (mounted) {
        setState(() {
          listening = false;
          error = 'Could not start microphone input. $exception';
        });
      }
    }
  }

  Future<void> submitReport() async {
    if (controller.text.trim().length < 4) {
      setState(
        () => error = 'Describe the issue in a few words before submitting.',
      );
      return;
    }
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/api/report'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'text': controller.text.trim(),
              'country': selectedCountry,
              'location': selectedLocation,
              'language': selectedLanguage,
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'The API returned ${response.statusCode}: ${response.body}',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Unexpected analysis response.');
      }
      if (!mounted) return;
      setState(() => result = decoded);
    } catch (exception) {
      if (!mounted) return;
      setState(
        () => error =
            'Could not analyze report. Check that the backend is running. $exception',
      );
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 850;
        final report = _buildReportCard(context);
        final analysis =
            result == null ? _buildInfoCard() : _buildAnalysisCard(result!);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: report),
                        const SizedBox(width: 20),
                        Expanded(flex: 4, child: analysis),
                      ],
                    )
                  : Column(
                      children: [report, const SizedBox(height: 18), analysis],
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReportCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeading(
              icon: Icons.campaign_outlined,
              title: 'Report a community issue',
              subtitle: 'Innovation begins by listening to communities.',
            ),
            const SizedBox(height: 16),
            const _InnovationBanner(
              title: 'BRICS innovation · Citizen voice to public good',
              description:
                  'Turn multilingual community needs into explainable, '
                  'data-informed development priorities.',
            ),
            const SizedBox(height: 24),
            const _FieldLabel('What is happening?'),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              minLines: 4,
              maxLines: 6,
              maxLength: 2000,
              decoration: const InputDecoration(
                hintText: 'Describe the problem, or tap Speak to dictate...',
                filled: true,
                fillColor: Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                  borderSide: BorderSide(color: Color(0xFFE1E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                  borderSide: BorderSide(color: Color(0xFFE1E8F0)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: toggleVoiceInput,
                  icon: Icon(
                      listening ? Icons.stop_circle_outlined : Icons.mic_none),
                  label: Text(listening ? 'Stop listening' : 'Speak'),
                ),
                OutlinedButton.icon(
                  onPressed: () => setState(() {
                    controller.text = 'మా గ్రామంలో తాగునీటి సమస్య ఉంది.';
                    selectedCountry = 'India';
                    selectedLocation = 'Guntur';
                    selectedLanguage = 'Auto-detect';
                  }),
                  icon: const Icon(Icons.translate),
                  label: const Text('Telugu example'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const _FieldLabel('Country'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: selectedCountry,
              decoration: const InputDecoration(
                filled: true,
                fillColor: Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              ),
              items: (countryOptions.isEmpty
                      ? const [
                          {'name': 'India'}
                        ]
                      : countryOptions)
                  .map(
                    (country) => DropdownMenuItem<String>(
                      value: country['name'].toString(),
                      child: Text(country['name'].toString()),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                final option = countryOptions.firstWhere(
                  (country) => country['name'] == value,
                  orElse: () => const {
                    'regions': ['Guntur']
                  },
                );
                setState(() {
                  selectedCountry = value;
                  selectedLocation =
                      (option['regions'] as List<dynamic>).first.toString();
                  selectedLanguage = 'Auto-detect';
                });
              },
            ),
            const SizedBox(height: 12),
            const _FieldLabel('Region'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: selectedLocation,
              decoration: const InputDecoration(
                filled: true,
                fillColor: Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              ),
              items: selectedRegions
                  .map(
                    (region) => DropdownMenuItem(
                      value: region,
                      child: Text(region),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => selectedLocation = value);
              },
            ),
            const SizedBox(height: 16),
            const _FieldLabel('Language'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: selectedLanguage,
              decoration: const InputDecoration(
                filled: true,
                fillColor: Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              ),
              items: ['Auto-detect', ...selectedLanguages]
                  .map(
                    (language) => DropdownMenuItem(
                      value: language,
                      child: Text(language),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => selectedLanguage = value);
              },
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: const TextStyle(color: Color(0xFFB42318))),
            ],
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: submitting ? null : submitReport,
                icon: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(submitting ? 'Analyzing...' : 'Submit report'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: blue,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Speech-to-text requires microphone permission and browser/device speech recognition support. Live messaging integrations are not connected.',
              style: TextStyle(color: muted, fontSize: 12, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeading(
              icon: Icons.auto_awesome,
              title: 'AI analysis',
              subtitle: 'Submit a report to see its structured result.',
            ),
            SizedBox(height: 22),
            _InfoTile(
              icon: Icons.translate,
              title: 'Language detection and translation',
            ),
            SizedBox(height: 10),
            _InfoTile(
              icon: Icons.category_outlined,
              title: 'Issue classification and severity',
            ),
            SizedBox(height: 10),
            _InfoTile(
              icon: Icons.insights_outlined,
              title: 'Explainable prototype priority score',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisCard(Map<String, dynamic> data) {
    final breakdown = data['score_breakdown'] as Map<String, dynamic>;
    final score = (data['priority_score'] as num).toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeading(
              icon: Icons.auto_awesome,
              title: 'AI analysis',
              subtitle: 'Structured from the submitted community report.',
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Tag(data['language'].toString(), const Color(0xFFEAF2FF)),
                _Tag(data['category'].toString(), const Color(0xFFEAF7F2)),
                _Tag(
                  '${data['priority']} priority',
                  _priorityColor(
                    data['priority'].toString(),
                  ).withValues(alpha: 0.12),
                  textColor: _priorityColor(data['priority'].toString()),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _ResultRow(
              label: 'Country / region',
              value: '${data['country']} / ${data['location']}',
            ),
            _ResultRow(label: 'Issue', value: data['issue'].toString()),
            _ResultRow(label: 'Severity', value: data['severity'].toString()),
            _ResultRow(
              label: 'Infrastructure index',
              value: '${data['infrastructure_index']}/100',
            ),
            _ResultRow(
              label: 'People affected',
              value: '~${data['people_affected']}',
            ),
            const Divider(height: 24),
            const _FieldLabel('Translation'),
            const SizedBox(height: 6),
            Text(data['translation'].toString()),
            const SizedBox(height: 16),
            const _FieldLabel('AI summary'),
            const SizedBox(height: 6),
            Text(
              data['summary'].toString(),
              style: const TextStyle(height: 1.5),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Prototype priority score',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${score.toStringAsFixed(1)} / 100',
                  style: const TextStyle(
                    color: blue,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: score / 100,
              minHeight: 8,
              borderRadius: BorderRadius.circular(99),
              backgroundColor: const Color(0xFFE9EEF5),
              color: blue,
            ),
            const SizedBox(height: 14),
            _ScoreLine(
              label: 'Citizen demand · 30%',
              value: breakdown['citizen_demand'],
            ),
            _ScoreLine(
              label: 'Infrastructure gap · 25%',
              value: breakdown['infrastructure_gap'],
            ),
            _ScoreLine(
              label: 'Population impact · 20%',
              value: breakdown['population_impact'],
            ),
            _ScoreLine(label: 'Urgency · 15%', value: breakdown['urgency']),
            _ScoreLine(
              label: 'Investment gap · 10%',
              value: breakdown['investment_gap'],
            ),
            const SizedBox(height: 10),
            Text(
              data['score_explanation'].toString(),
              style: const TextStyle(color: muted, fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 14),
            _InfoTile(
              icon: Icons.lightbulb_outline,
              title: data['recommendation'].toString(),
            ),
            const SizedBox(height: 8),
            _InfoTile(
              icon: Icons.account_balance_outlined,
              title: data['investment_plan'].toString(),
            ),
            const SizedBox(height: 12),
            const Text(
              'Demo heuristic only—not an official government allocation formula.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class GovernmentDashboardPage extends StatefulWidget {
  const GovernmentDashboardPage({super.key});

  @override
  State<GovernmentDashboardPage> createState() =>
      _GovernmentDashboardPageState();
}

class _GovernmentDashboardPageState extends State<GovernmentDashboardPage> {
  late Future<Map<String, dynamic>> dashboardFuture;
  String selectedCountry = 'All BRICS';
  WebSocketChannel? dashboardChannel;
  StreamSubscription<dynamic>? dashboardSubscription;
  Timer? reconnectTimer;
  bool realtimeConnected = false;

  @override
  void initState() {
    super.initState();
    dashboardFuture = fetchDashboard();
    connectToDashboard();
  }

  void connectToDashboard() {
    if (!mounted) return;
    final apiUri = Uri.parse(apiBaseUrl);
    final socketUri = apiUri.replace(
      scheme: apiUri.scheme == 'https' ? 'wss' : 'ws',
      path: '/ws/dashboard',
      query: null,
      fragment: null,
    );
    try {
      final channel = WebSocketChannel.connect(socketUri);
      dashboardChannel = channel;
      channel.ready.then(
        (_) {
          if (mounted && identical(dashboardChannel, channel)) {
            setState(() => realtimeConnected = true);
          }
        },
        onError: (Object _) => scheduleDashboardReconnect(channel),
      );
      dashboardSubscription = channel.stream.listen(
        (event) {
          if (event is! String) return;
          final message = jsonDecode(event);
          if (message is Map<String, dynamic> &&
              message['type'] == 'report_created' &&
              mounted) {
            setState(() {
              dashboardFuture = fetchDashboard();
            });
          }
        },
        onError: (Object _) => scheduleDashboardReconnect(channel),
        onDone: () => scheduleDashboardReconnect(channel),
      );
    } catch (_) {
      scheduleDashboardReconnect(dashboardChannel);
    }
  }

  void scheduleDashboardReconnect(WebSocketChannel? channel) {
    if (!mounted ||
        (channel != null && !identical(dashboardChannel, channel))) {
      return;
    }
    setState(() => realtimeConnected = false);
    reconnectTimer?.cancel();
    reconnectTimer = Timer(const Duration(seconds: 2), connectToDashboard);
  }

  Future<Map<String, dynamic>> fetchDashboard({String? country}) async {
    final uri = Uri.parse('$apiBaseUrl/api/dashboard').replace(
      queryParameters: {'country': country ?? selectedCountry},
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Dashboard API returned ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected dashboard response.');
    }
    return decoded;
  }

  @override
  void dispose() {
    reconnectTimer?.cancel();
    dashboardSubscription?.cancel();
    dashboardChannel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: dashboardFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 42, color: muted),
                  const SizedBox(height: 12),
                  const Text('Could not load the dashboard.'),
                  const SizedBox(height: 8),
                  Text(
                    snapshot.error.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: muted),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => setState(() {
                      dashboardFuture = fetchDashboard();
                    }),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        final metrics = data['metrics'] as Map<String, dynamic>;
        final areas = data['priority_areas'] as List<dynamic>;
        final recommendations = data['recommendations'] as List<dynamic>;
        final recentReports = data['recent_reports'] as List<dynamic>;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1250),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeading(
                    icon: Icons.admin_panel_settings_outlined,
                    title: 'Government dashboard',
                    subtitle:
                        'Innovation for inclusive, evidence-informed development.',
                  ),
                  const SizedBox(height: 14),
                  const _InnovationBanner(
                    title: 'Listen locally. Learn across BRICS.',
                    description:
                        'A civic-tech approach to discovering needs and '
                        'sharing scalable public-service ideas.',
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 10,
                        color: realtimeConnected
                            ? const Color(0xFF1B9B78)
                            : const Color(0xFFE39A10),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        realtimeConnected
                            ? 'Live updates connected'
                            : 'Reconnecting to live updates…',
                        style: const TextStyle(
                          color: muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: 320,
                    child: DropdownButtonFormField<String>(
                      initialValue: selectedCountry,
                      decoration: const InputDecoration(
                        labelText: 'Country view',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'All BRICS',
                          child: Text('All BRICS countries'),
                        ),
                        for (final country
                            in data['countries'] as List<dynamic>)
                          DropdownMenuItem<String>(
                            value: country['name'].toString(),
                            child: Text(country['name'].toString()),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          selectedCountry = value;
                          dashboardFuture = fetchDashboard(country: value);
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth > 900
                          ? 4
                          : constraints.maxWidth > 550
                              ? 2
                              : 1;
                      return GridView.count(
                        crossAxisCount: columns,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: columns == 1 ? 2.8 : 1.9,
                        children: [
                          _MetricCard(
                            label: 'Citizen requests',
                            value: _number(metrics['citizen_requests']),
                            icon: Icons.forum_outlined,
                            color: blue,
                          ),
                          _MetricCard(
                            label: 'Critical issues',
                            value: _number(metrics['critical_issues']),
                            icon: Icons.priority_high_rounded,
                            color: const Color(0xFFD94343),
                          ),
                          _MetricCard(
                            label: 'Infrastructure gaps',
                            value: _number(metrics['infrastructure_gaps']),
                            icon: Icons.warning_amber_rounded,
                            color: const Color(0xFFE39A10),
                          ),
                          _MetricCard(
                            label: 'Regions covered',
                            value: _number(metrics['districts_covered']),
                            icon: Icons.map_outlined,
                            color: const Color(0xFF1B9B78),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildHotspotMap(data['hotspots'] as List<dynamic>),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final priorityCard = _buildPriorityAreas(areas);
                      final projectsCard = _buildRecommendations(
                        recommendations,
                      );
                      if (constraints.maxWidth < 850) {
                        return Column(
                          children: [
                            priorityCard,
                            const SizedBox(height: 16),
                            projectsCard,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: priorityCard),
                          const SizedBox(width: 16),
                          Expanded(flex: 2, child: projectsCard),
                        ],
                      );
                    },
                  ),
                  if (recentReports.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildRecentReports(recentReports),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    data['prototype_notice'].toString(),
                    style: const TextStyle(
                      color: muted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHotspotMap(List<dynamic> hotspots) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            const Row(
              children: [
                Icon(Icons.map_outlined, color: blue),
                SizedBox(width: 8),
                Text(
                  'Infrastructure gap map',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 225,
              width: double.infinity,
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE8F1FB), Color(0xFFDDE9F5)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(painter: _WorldMapPainter()),
                    ),
                    for (final hotspot in hotspots)
                      _mapHotspotFromData(constraints, hotspot),
                    const Positioned(
                      left: 12,
                      bottom: 10,
                      child: Text(
                        'Schematic BRICS coverage · illustrative regional markers',
                        style: TextStyle(color: muted, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                _Legend(color: Color(0xFFD94343), label: 'High / Critical'),
                _Legend(color: Color(0xFFE39A10), label: 'Medium'),
                _Legend(color: Color(0xFF1B9B78), label: 'Low'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityAreas(List<dynamic> areas) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Top priority areas',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            const SizedBox(height: 14),
            for (final item in areas)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 11,
                      color: _priorityColor(item['priority'].toString()),
                    ),
                    const SizedBox(width: 9),
                    Expanded(child: Text(item['category'].toString())),
                    Text(
                      '${item['requests']} requests',
                      style: const TextStyle(
                        color: muted,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentReports(List<dynamic> reports) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Latest citizen reports',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            const SizedBox(height: 12),
            for (final item in reports.take(8))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.circle,
                  size: 13,
                  color: _priorityColor(item['priority'].toString()),
                ),
                title: Text(
                  '${item['category']} · ${item['issue']}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${item['location']} · ${item['language']} · ${item['severity']}',
                ),
                trailing: Text(
                  item['priority_score'].toString(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _mapHotspot(
    BoxConstraints constraints,
    double horizontal,
    double vertical,
    String label,
    Color color,
  ) {
    return Positioned(
      left: constraints.maxWidth * horizontal,
      top: 225 * vertical,
      child: Tooltip(
        message: label,
        child: Container(
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: .35), blurRadius: 9),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mapHotspotFromData(
    BoxConstraints constraints,
    dynamic hotspot,
  ) {
    final latitude = (hotspot['latitude'] as num).toDouble();
    final longitude = (hotspot['longitude'] as num).toDouble();
    final left = ((longitude + 180) / 360).clamp(.04, .96);
    final top = ((90 - latitude) / 180).clamp(.08, .84);
    return _mapHotspot(
      constraints,
      left,
      top,
      '${hotspot['district']}, ${hotspot['country']}',
      _priorityColor(hotspot['priority'].toString()),
    );
  }

  Widget _buildRecommendations(List<dynamic> recommendations) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AI development recommendations',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            const SizedBox(height: 14),
            for (final project in recommendations)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F9FC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE7EDF4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.lightbulb_outline, color: blue),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            project['project'].toString(),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        _Tag(
                          project['priority'].toString().toUpperCase(),
                          _priorityColor(
                            project['priority'].toString(),
                          ).withValues(alpha: .12),
                          textColor: _priorityColor(
                            project['priority'].toString(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '📍 ${project['location']}   ·   👥 ${_number(project['population'])} affected',
                      style: const TextStyle(color: muted, fontSize: 13),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '📊 ${project['requests']} requests   ·   Index ${project['infrastructure_index']}/100   ·   💰 ${project['estimate']}',
                      style: const TextStyle(color: muted, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      project['explanation'].toString(),
                      style: const TextStyle(
                        color: muted,
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text(
                          'Prototype score',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: LinearProgressIndicator(
                            value:
                                (project['priority_score'] as num).toDouble() /
                                    100,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(99),
                            color: _priorityColor(
                              project['priority'].toString(),
                            ),
                            backgroundColor: const Color(0xFFE4EAF1),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${project['priority_score']}/100'),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: blue),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(color: muted, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}

class _InnovationBanner extends StatelessWidget {
  const _InnovationBanner({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF2FF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD7E6FA)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lightbulb_outline, color: blue),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      color: muted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      );
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6EBF1)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: blue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(color: muted)),
            ),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _ScoreLine extends StatelessWidget {
  const _ScoreLine({required this.label, required this.value});
  final String label;
  final dynamic value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ),
            Text(
              '${(value as num).toStringAsFixed(0)}/100',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ],
        ),
      );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color),
              Text(
                value,
                style:
                    const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
              ),
              Text(label, style: const TextStyle(color: muted, fontSize: 12)),
            ],
          ),
        ),
      );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.background, {this.textColor = ink});
  final String text;
  final Color background;
  final Color textColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: textColor,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: muted, fontSize: 12)),
        ],
      );
}

class _WorldMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final land = Paint()
      ..color = const Color(0xFF7894B1).withValues(alpha: .25)
      ..style = PaintingStyle.fill;
    final outline = Paint()
      ..color = const Color(0xFF7894B1).withValues(alpha: .42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final continents = [
      [
        const Offset(.08, .25),
        const Offset(.13, .16),
        const Offset(.24, .15),
        const Offset(.29, .25),
        const Offset(.24, .34),
        const Offset(.22, .47),
        const Offset(.18, .62),
        const Offset(.12, .52),
        const Offset(.09, .38),
      ],
      [
        const Offset(.23, .55),
        const Offset(.31, .52),
        const Offset(.35, .61),
        const Offset(.33, .74),
        const Offset(.29, .91),
        const Offset(.25, .80),
        const Offset(.23, .66),
      ],
      [
        const Offset(.43, .20),
        const Offset(.50, .15),
        const Offset(.60, .19),
        const Offset(.65, .27),
        const Offset(.61, .34),
        const Offset(.53, .32),
        const Offset(.49, .39),
        const Offset(.45, .32),
      ],
      [
        const Offset(.48, .41),
        const Offset(.57, .39),
        const Offset(.62, .49),
        const Offset(.59, .66),
        const Offset(.55, .83),
        const Offset(.50, .72),
        const Offset(.47, .55),
      ],
      [
        const Offset(.62, .22),
        const Offset(.72, .16),
        const Offset(.86, .18),
        const Offset(.94, .29),
        const Offset(.89, .42),
        const Offset(.79, .44),
        const Offset(.73, .36),
        const Offset(.65, .39),
        const Offset(.60, .31),
      ],
      [
        const Offset(.80, .52),
        const Offset(.88, .49),
        const Offset(.91, .59),
        const Offset(.87, .70),
        const Offset(.81, .65),
      ],
    ];
    for (final points in continents) {
      final path = Path()
        ..moveTo(points.first.dx * size.width, points.first.dy * size.height);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx * size.width, point.dy * size.height);
      }
      path.close();
      canvas.drawPath(path, land);
      canvas.drawPath(path, outline);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

String _number(dynamic value) {
  final number = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  return number.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (match) => '${match[1]},',
      );
}

String? _speechLocale(String language) {
  const locales = {
    'English': 'en-IN',
    'Portuguese': 'pt-BR',
    'Chinese (Mandarin)': 'zh-CN',
    'Telugu': 'te-IN',
    'Hindi': 'hi-IN',
    'Tamil': 'ta-IN',
    'Kannada': 'kn-IN',
    'Bengali': 'bn-IN',
    'Russian': 'ru-RU',
    'isiZulu': 'zu-ZA',
    'isiXhosa': 'xh-ZA',
    'Afrikaans': 'af-ZA',
  };
  return locales[language];
}

Color _priorityColor(String priority) {
  switch (priority.toLowerCase()) {
    case 'critical':
    case 'high':
      return const Color(0xFFD94343);
    case 'medium':
      return const Color(0xFFE39A10);
    default:
      return const Color(0xFF1B9B78);
  }
}

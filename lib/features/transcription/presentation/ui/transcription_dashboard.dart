import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/ipc/ipc_message.dart';
import '../../data/local_ipc_transcription_service.dart';
import '../../../../core/database/sqlite_database_repository.dart';
import '../../../../core/hardware/hardware_scanner.dart';

class TranscriptionDashboard extends StatefulWidget {
  final Talker talker;
  final int ipcPort;

  const TranscriptionDashboard({super.key, required this.talker, required this.ipcPort});

  @override
  State<TranscriptionDashboard> createState() => _TranscriptionDashboardState();
}

class TranscriptBlock {
  final String text;
  final String signature;
  final String language;
  final int timestamp;
  final bool isTranslated;

  TranscriptBlock({
    required this.text, 
    required this.signature, 
    required this.language, 
    required this.timestamp,
    this.isTranslated = false,
  });
}

class _TranscriptionDashboardState extends State<TranscriptionDashboard> {
  late LocalIpcTranscriptionService _transcriptionService;
  final HardwareScanner _scanner = HardwareScannerFactory.getScanner();
  
  // State
  final List<TranscriptBlock> _transcripts = [];
  final Map<String, String> _speakerTags = {};
  final Map<String, TextEditingController> _tagControllers = {}; 
  
  bool _isMeetingActive = false;
  bool _isConnectedToEngine = false;
  String _captureStatusLine = 'Capture: Idle';
  double _volumeLevel = 0.0;
  DateTime _lastSignalTime = DateTime.now().subtract(const Duration(seconds: 10));
  
  // Hardware/Model Statuses
  final Map<String, String> _modelStatuses = {}; 
  PerformanceTier _tier = PerformanceTier.standard;
  Map<String, dynamic> _hardwareSpecs = {};
  
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _transcriptionService = LocalIpcTranscriptionService(port: widget.ipcPort);
    _initHardware();
    _connectToEngine();
  }

  Future<void> _initHardware() async {
    final tier = await _scanner.getTier();
    final specs = await _scanner.getHardwareSpecs();
    setState(() {
      _tier = tier;
      _hardwareSpecs = specs;
    });
  }
  
  Future<void> _connectToEngine() async {
    try {
      await _transcriptionService.connect();
      setState(() => _isConnectedToEngine = true);
      
      _transcriptionService.logStream.listen((logMsg) {
        widget.talker.info(logMsg);
      });
      
      _transcriptionService.rawMessageStream.listen((rawJson) {
        final msg = IpcMessage.fromJson(rawJson);
        
        if (msg.type == 'TRANSCRIPT') {
          final payload = msg.payload;
          final signature = payload['signature'] ?? 'Unknown';
          final language = payload['language'] ?? 'Unknown';
          final text = payload['text'] ?? '';
          final translated = payload['translated'] ?? false;

          setState(() {
            _transcripts.add(TranscriptBlock(
              text: text, 
              signature: signature, 
              language: language,
              timestamp: DateTime.now().millisecondsSinceEpoch,
              isTranslated: translated,
            ));
            
            if (!_speakerTags.containsKey(signature)) {
              _speakerTags[signature] = signature;
              _tagControllers[signature] = TextEditingController(text: signature);
            }
          });
          _scrollToBottom();
        } 
        else if (msg.type == 'VOLUME') {
          setState(() {
            _volumeLevel = (msg.payload['level'] as num).toDouble();
            if (_volumeLevel > 0.001) _lastSignalTime = DateTime.now();
          });
        } 
        else if (msg.type == 'MODEL_STATUS') {
          setState(() {
            _modelStatuses[msg.payload['modelName']] = msg.payload['status'];
          });
        }
        else if (msg.type == 'CONTROL') {
          final action = msg.payload['action'];
          if (action == 'ENGINE_ACTIVE') {
            setState(() => _isMeetingActive = true);
          } else if (action == 'ENGINE_IDLE') {
            setState(() {
               _isMeetingActive = false;
               _volumeLevel = 0;
            });
          }
        }
      });
    } catch (e) {
      widget.talker.error("Failed to connect to IPC engine: $e");
      setState(() => _isConnectedToEngine = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toggleMeeting() {
    if (!_isConnectedToEngine) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cannot start: Not connected to Background Engine.")),
      );
      return;
    }

    if (_isMeetingActive) {
      _transcriptionService.stopMeeting();
    } else {
      _transcripts.clear(); 
      _transcriptionService.startMeeting();
    }
  }
  
  void _updateSpeakerTag(String signature, String newName) {
    if (_speakerTags[signature] != newName) {
      setState(() {
        _speakerTags[signature] = newName;
      });
      _transcriptionService.updateTag(signature, newName);
    }
  }

  Future<void> _exportSession(String format) async {
    final database = SqliteDatabaseRepository();
    await database.initialize();
    final rows = await database.getSessionTranscripts();
    
    String content = "";
    String extension = "";
    
    if (format == 'JSON') {
      content = jsonEncode(rows);
      extension = "json";
    } else if (format == 'SRT') {
      extension = "srt";
      for (int i = 0; i < rows.length; i++) {
        final row = rows[i];
        final start = DateTime.fromMillisecondsSinceEpoch(row['timestamp']);
        final end = start.add(const Duration(seconds: 3));
        
        String formatTime(DateTime dt) {
          return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')},000";
        }
        
        content += "${i + 1}\n";
        content += "${formatTime(start)} --> ${formatTime(end)}\n";
        content += "[${row['speaker_name']}] [${row['language'].toString().toUpperCase()}]: ${row['text']}\n\n";
      }
    }
    
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/vigyan_export_${DateTime.now().millisecondsSinceEpoch}.$extension');
    await file.writeAsString(content);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Exported to: ${file.path}")),
      );
    }
  }

  Widget _buildStatusChip(String name, String status) {
    Color color = Colors.grey;
    IconData icon = Icons.help_outline;
    
    if (status == 'loading') {
      color = Colors.orange;
      icon = Icons.sync;
    } else if (status == 'success') {
      color = Colors.green;
      icon = Icons.check_circle;
    } else if (status == 'missing') {
      color = Colors.red;
      icon = Icons.download_for_offline;
    } else if (status == 'error') {
      color = Colors.red;
      icon = Icons.error;
    }

    return Tooltip(
      message: "$name: ${status.toUpperCase()}",
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (status == 'loading')
              const SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
              )
            else
              Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              name.split(' ').first, 
              style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVolumeGauge(ThemeData theme) {
    final bool isSignalActive = DateTime.now().difference(_lastSignalTime).inMilliseconds < 500;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSignalActive ? Colors.blueAccent : Colors.grey.shade800,
                boxShadow: isSignalActive ? [
                  BoxShadow(color: Colors.blueAccent.withOpacity(0.5), blurRadius: 4, spreadRadius: 1)
                ] : [],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              isSignalActive ? 'SIGNAL REACHING BACKGROUND' : 'WAITING FOR SIGNAL',
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 8,
                color: isSignalActive ? Colors.blueAccent : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: List.generate(20, (index) {
            final threshold = index / 20.0;
            final isActive = _volumeLevel > threshold;
            Color barColor = Colors.green;
            if (index > 12) barColor = Colors.orange;
            if (index > 16) barColor = Colors.red;
            
            return Container(
              width: 4,
              height: 10,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: isActive ? barColor : barColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(1),
              ),
            );
          }),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _transcriptionService.dispose();
    for (var controller in _tagControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: _buildAppBar(theme),
      drawer: _buildDrawer(theme),
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: _buildTranscriptFeed(theme),
          ),
          VerticalDivider(width: 1, color: theme.colorScheme.outlineVariant),
          Expanded(
            flex: 1,
            child: _buildRightPanel(theme),
          ),
        ],
      ),
    );
  }

  AppBar _buildAppBar(ThemeData theme) {
    return AppBar(
      backgroundColor: theme.colorScheme.surfaceContainer,
      toolbarHeight: 80, 
      elevation: 0,
      title: Row(
        children: [
          Image.asset(
            'assets/VigyanBytes_Logo_Master.webp',
            height: 44,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _isConnectedToEngine ? Colors.green.withOpacity(0.1) : theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _isConnectedToEngine ? Colors.green : theme.colorScheme.error),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isConnectedToEngine ? Icons.link : Icons.link_off, 
                            size: 14, 
                            color: _isConnectedToEngine ? Colors.green : theme.colorScheme.error
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _isConnectedToEngine ? 'ENGINE ${_isMeetingActive ? "ACTIVE" : "IDLE"}' : 'DISCONNECTED',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: _isConnectedToEngine ? Colors.green : theme.colorScheme.onErrorContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Hardware/Software Metadata
                    Text(
                      'HW: ${_hardwareSpecs["accelerator"] ?? "Scanning..."} | SW: ONNX Runtime / SQLite-Vec',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ..._modelStatuses.entries.map((e) => _buildStatusChip(e.key, e.value)).toList(),
                    if (_isMeetingActive) ...[
                      const SizedBox(width: 16),
                      Expanded(child: _buildVolumeGauge(theme)),
                    ]
                  ],
                ),
              ],
            ),
          )
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.bug_report),
          tooltip: "View Logs",
          onPressed: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (context) => TalkerScreen(talker: widget.talker),
            ));
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildDrawer(ThemeData theme) {
    return NavigationDrawer(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hardware Profile', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
              Text('Tier: ${_tier.name.toUpperCase()} | OS: ${_hardwareSpecs["os"]}', style: theme.textTheme.labelSmall),
              Text('Accel: ${_hardwareSpecs["accelerator"]}', style: theme.textTheme.labelSmall),
            ],
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
          child: Text('Service Controls', style: theme.textTheme.titleMedium),
        ),
        NavigationDrawerDestination(
          icon: Icon(
            _isMeetingActive ? Icons.stop_circle_outlined : Icons.play_circle_outline,
            color: _isMeetingActive ? theme.colorScheme.error : theme.colorScheme.primary,
          ),
          selectedIcon: Icon(
            _isMeetingActive ? Icons.stop_circle : Icons.play_circle,
            color: _isMeetingActive ? theme.colorScheme.error : theme.colorScheme.primary,
          ),
          label: Text(_isMeetingActive ? 'Stop Capture Engine' : 'Start Capture Engine'),
        ),
        ListTile(
          leading: const Icon(Icons.sensors),
          title: const Text('Capture Source (Automatic)'),
          subtitle: Text(_captureStatusLine),
        ),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 28), child: Divider()),
        NavigationDrawerDestination(
          icon: const Icon(Icons.refresh),
          label: const Text('Reconnect IPC'),
        ),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 28), child: Divider()),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 10),
          child: Text('Export Results', style: theme.textTheme.labelMedium),
        ),
        NavigationDrawerDestination(
          icon: const Icon(Icons.description_outlined),
          label: const Text('Export as JSON'),
        ),
        NavigationDrawerDestination(
          icon: const Icon(Icons.subtitles_outlined),
          label: const Text('Export as SRT'),
        ),
      ],
      onDestinationSelected: (index) {
        if (index == 0) {
          _toggleMeeting();
          Navigator.pop(context);
        } else if (index == 1) {
          if (!_isConnectedToEngine) _connectToEngine();
          Navigator.pop(context);
        } else if (index == 2) {
          _exportSession('JSON');
          Navigator.pop(context);
        } else if (index == 3) {
          _exportSession('SRT');
          Navigator.pop(context);
        }
      },
    );
  }

  Widget _buildTranscriptFeed(ThemeData theme) {
    if (_transcripts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mic_none, size: 64, color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(
              _isMeetingActive ? 'Listening for audio...' : 'Open the menu to Start Capture',
              style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(24.0),
      itemCount: _transcripts.length,
      itemBuilder: (context, index) {
        final block = _transcripts[index];
        final displayName = _speakerTags[block.signature] ?? 'Unknown';
        
        final colorHash = block.signature.hashCode;
        final avatarColor = Color.fromARGB(
          255, 
          100 + (colorHash % 100), 
          100 + ((colorHash ~/ 100) % 100), 
          150 + ((colorHash ~/ 10000) % 100)
        );

        return Padding(
          padding: const EdgeInsets.only(bottom: 24.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: avatarColor,
                radius: 20,
                child: Text(
                  displayName.substring(0, 1).toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          displayName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            block.language.toUpperCase(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (block.isTranslated) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.translate, size: 14, color: theme.colorScheme.primary),
                        ]
                      ],
                    ),
                    const SizedBox(height: 6),
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerHighest,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          block.text,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.5,
                            fontSize: 16, 
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRightPanel(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Participants',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (_speakerTags.isEmpty)
            Text("No signatures detected yet.", style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          
          Expanded(
            child: ListView.builder(
              itemCount: _speakerTags.length,
              itemBuilder: (context, index) {
                final sig = _speakerTags.keys.elementAt(index);
                final controller = _tagControllers[sig]!;
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Voice ID: ${sig.length > 8 ? "...${sig.substring(sig.length - 8)}" : sig}',
                        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: controller,
                        style: theme.textTheme.bodyLarge,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          filled: true,
                          fillColor: theme.colorScheme.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
                          ),
                          hintText: 'Tag participant...',
                        ),
                        onSubmitted: (val) {
                          if (val.isNotEmpty) _updateSpeakerTag(sig, val);
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

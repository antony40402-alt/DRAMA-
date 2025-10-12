
import 'dart:convert';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FYJHApp());
}

class FYJHApp extends StatelessWidget {
  const FYJHApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FYJH 劇本台詞練習器',
      theme: ThemeData(
        colorSchemeSeed: Colors.black,
        useMaterial3: true,
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
  late Future<Script> _script;
  int actIdx = 0;
  int sceneIdx = 0;
  String role = 'A';
  int cursor = 0;
  bool aiPartner = true;
  bool autoNext = true;

  final FlutterTts tts = FlutterTts();
  final Record recorder = Record();
  final AudioPlayer player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _script = _loadScript();
    _initTts();
  }

  Future<void> _initTts() async {
    await tts.setLanguage('zh-TW');
    await tts.setSpeechRate(0.52);
    await tts.setPitch(1.0);
    await tts.setVolume(1.0);
  }

  Future<Script> _loadScript() async {
    final s = await rootBundle.loadString('assets/script.json');
    return Script.fromJson(jsonDecode(s));
  }

  @override
  void dispose() {
    tts.stop();
    player.dispose();
    recorder.dispose();
    super.dispose();
  }

  Future<Directory> _audioDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final d = Directory('${dir.path}/recordings');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<void> _startRec() async {
    if (!await Permission.microphone.request().isGranted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要麥克風權限才能錄音')),
        );
      }
      return;
    }
    final d = await _audioDir();
    final now = DateTime.now().millisecondsSinceEpoch;
    final path = '${d.path}/a${actIdx}_s${sceneIdx}_l${cursor}_$now.m4a';
    await recorder.start(
      path: path,
      encoder: AudioEncoder.aacLc,
      bitRate: 128000,
      samplingRate: 44100,
    );
    setState(() {});
  }

  Future<void> _stopRec() async {
    final filePath = await recorder.stop();
    if (filePath != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已儲存錄音：${filePath.split('/').last}')),
      );
      setState(() {});
    }
  }

  bool get isRecording => recorder.isRecording();

  Future<List<FileSystemEntity>> _lineFiles() async {
    final d = await _audioDir();
    final pattern = RegExp('a${actIdx}_s${sceneIdx}_l${cursor}_');
    final all = d.listSync().where((f) => f.path.endsWith('.m4a')).toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return all.where((e) => pattern.hasMatch(e.path)).toList();
  }

  Future<void> _speak(String who, String text) async {
    await tts.stop();
    await tts.speak('${who == "舞台" ? "舞台指示" : who}：$text');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _script,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final script = snap.data! as Script;
        final acts = script.acts;
        final scenes = acts[actIdx].scenes;
        final lines = scenes[sceneIdx].lines;
        cursor = cursor.clamp(0, lines.length - 1);

        return Scaffold(
          appBar: AppBar(
            title: const Text('FYJH 劇本台詞練習器'),
            actions: [
              IconButton(
                tooltip: aiPartner ? 'AI 對戲：開' : 'AI 對戲：關',
                onPressed: () => setState(() => aiPartner = !aiPartner),
                icon: Icon(aiPartner ? Icons.record_voice_over : Icons.voice_over_off_outlined),
              ),
              IconButton(
                tooltip: autoNext ? '自動前進：開' : '自動前進：關',
                onPressed: () => setState(() => autoNext = !autoNext),
                icon: Icon(autoNext ? Icons.skip_next : Icons.skip_next_outlined),
              ),
            ],
          ),
          body: Column(
            children: [
              // selectors
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _dropdown('幕', acts.mapIndexed((i,a)=>DropdownMenuItem(value:i,child: Text('${a.act}｜${a.title}'))).toList(), actIdx, (v){
                      setState(() { actIdx = v!; sceneIdx = 0; cursor = 0; });
                    }),
                    _dropdown('景', scenes.mapIndexed((i,s)=>DropdownMenuItem(value:i,child: Text(s.scene))).toList(), sceneIdx, (v){
                      setState(() { sceneIdx = v!; cursor = 0; });
                    }),
                    _roleChips(),
                    const SizedBox(width: 12),
                    FilledButton.tonal(onPressed: ()=> setState(()=> cursor = (cursor-1).clamp(0, lines.length-1)), child: const Text('上一句')),
                    FilledButton(onPressed: ()=> setState(()=> cursor = (cursor+1).clamp(0, lines.length-1)), child: const Text('下一句')),
                  ],
                ),
              ),
              // meta
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Row(
                  children: [
                    Text('目前：第 ${cursor+1} / ${lines.length} 句', style: TextStyle(color: Colors.grey[600])),
                    const SizedBox(width: 12),
                    Text('${acts[actIdx].act}｜${acts[actIdx].title}｜${scenes[sceneIdx].scene}', style: TextStyle(color: Colors.grey[600])),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: lines.length,
                  itemBuilder: (context, i) {
                    final ln = lines[i];
                    final isMine = ln.s.split('/').contains(role);
                    final isCurrent = i == cursor;
                    return Card(
                      color: isCurrent ? Colors.grey.shade100 : null,
                      elevation: isCurrent ? 1.5 : 0,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                              _pill(ln.s, context),
                              if (isMine) _pill('我的台詞', context, color: Colors.green.shade50, border: Colors.green.shade200),
                              if (isCurrent) _pill('目前', context, color: Colors.black, fg: Colors.white),
                            ]),
                            const SizedBox(height: 6),
                            SelectableText(ln.t),
                            if (i == cursor) _recControls(),
                            if (i == cursor) FutureBuilder(
                              future: _lineFiles(),
                              builder:(context,snap){
                                final files = (snap.data ?? []) as List<FileSystemEntity>;
                                if (files.isEmpty) return const SizedBox.shrink();
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 8),
                                    const Text('我的錄音：', style: TextStyle(fontWeight: FontWeight.w600)),
                                    ...files.map((f)=>_audioRow(File(f.path))).toList(),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(child: OutlinedButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('開始（AI 對戲）'),
                    onPressed: () async {
                      final ln = lines[cursor];
                      final isMine = ln.s.split('/').contains(role);
                      if (!isMine && aiPartner) { await _speak(ln.s, ln.t); }
                      if (autoNext) setState(()=> cursor = (cursor+1).clamp(0, lines.length-1));
                    },
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: OutlinedButton.icon(
                    icon: const Icon(Icons.stop),
                    label: const Text('停止朗讀'),
                    onPressed: () async { await tts.stop(); },
                  )),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _dropdown<T>(String label, List<DropdownMenuItem<T>> items, T value, void Function(T?) onChanged) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label：'),
      const SizedBox(width: 6),
      DropdownButton<T>(items: items, value: value, onChanged: onChanged),
    ]);
  }

  Widget _roleChips() {
    const roles = ['A','B','C','D','E','所有人','C/D','舞台'];
    return Wrap(
      spacing: 6,
      children: roles.map((r){
        final selected = r == role;
        return ChoiceChip(
          label: Text(r),
          selected: selected,
          onSelected: (_){ setState(()=> role = r); },
        );
      }).toList(),
    );
  }

  Widget _pill(String text, BuildContext context, {Color? color, Color? fg, Color? border}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color ?? Colors.grey.shade50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border ?? Colors.grey.shade300),
      ),
      child: Text(text, style: TextStyle(color: fg ?? Colors.black87, fontSize: 12)),
    );
  }

  Widget _recControls() {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Row(children: [
        ElevatedButton.icon(
          icon: Icon(isRecording ? Icons.stop : Icons.mic),
          label: Text(isRecording ? '停止錄音' : '開始錄音'),
          onPressed: () async {
            if (await recorder.isRecording()) {
              await _stopRec();
            } else {
              await _startRec();
            }
            setState(() {});
          },
        ),
        const SizedBox(width: 12),
        Text(isRecording ? '錄音中…' : '可錄下你的台詞並保存在本機'),
      ]),
    );
  }

  Widget _audioRow(File f) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(f.path.split('/').last),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(icon: const Icon(Icons.play_arrow), onPressed: () async { await player.setFilePath(f.path); await player.play(); }),
        IconButton(icon: const Icon(Icons.share), onPressed: () async {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請在「檔案」App 中前往本 App 的檔案夾分享錄音。')));
        }),
      ]),
    );
  }
}

// ===== Models =====
class Script {
  final List<Act> acts;
  Script({required this.acts});
  factory Script.fromJson(dynamic json) => Script(
    acts: (json as List).map((a)=>Act.fromJson(a)).toList()
  );
}
class Act {
  final String act;
  final String title;
  final List<Scene> scenes;
  Act({required this.act, required this.title, required this.scenes});
  factory Act.fromJson(dynamic j) => Act(
    act: j['act'], title: j['title'],
    scenes: (j['scenes'] as List).map((s)=>Scene.fromJson(s)).toList(),
  );
}
class Scene {
  final String scene;
  final List<Line> lines;
  Scene({required this.scene, required this.lines});
  factory Scene.fromJson(dynamic j) => Scene(
    scene: j['scene'], lines: (j['lines'] as List).map((l)=>Line.fromJson(l)).toList(),
  );
}
class Line {
  final String s;
  final String t;
  Line({required this.s, required this.t});
  factory Line.fromJson(dynamic j) => Line(s: j['s'], t: j['t']);
}

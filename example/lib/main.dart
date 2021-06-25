import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:csl_video_process/csl_video_process.dart';
import 'package:file_selector/file_selector.dart';
import 'dart:io';

import './video_thumbnail.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key? key, this.title}) : super(key: key);

  final String? title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String _counter = "video";

  _compressVideo() async {
    var file;
    if (Platform.isMacOS) {
      final typeGroup = XTypeGroup(label: 'videos', extensions: ['mov', 'mp4']);
      file = await openFile(acceptedTypeGroups: [typeGroup]);
    } else {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowCompression: false,
      );

      if (result == null) {
        return;
      }
      print('pickedImage path: ${result.files.single.path}');
      print('pickedImage size: ${result.files.single.size}');

      file = File(result.files.single.path!);
    }
    if (file == null) {
      return;
    }
    await VideoCompress.setLogLevel(0);
    final MediaInfo? info = await VideoCompress.compressVideo(
      file.path,
      sessionId: 123,
      startTimeMs: 0.1234,
      endTimeMs: 14000.331,
      rotation: 90,
    );
    print(info!.path);
    if (info != null) {
      setState(() {
        _counter = info.path!;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title!),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'You have pushed the button this many times:',
            ),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headline4,
            ),
            InkWell(
                child: Icon(
                  Icons.cancel,
                  size: 55,
                ),
                onTap: () {
                  VideoCompress.deleteSessionCache(sessionId: 123);
                }),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => VideoThumbnail()),
                );
              },
              child: Text('Test thumbnail'),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async => _compressVideo(),
        tooltip: 'Increment',
        child: Icon(Icons.add),
      ),
    );
  }
}

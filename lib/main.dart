import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initNotifications();
  tz.initializeTimeZones();
  runApp(MyApp());
}

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('app_icon');
  final IOSInitializationSettings initializationSettingsIOS =
      IOSInitializationSettings();
  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '薬飲み忘れ防止アプリ',
      theme: ThemeData(
        primarySwatch: Colors.orange,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
        ),
        textTheme: TextTheme(
          bodyLarge: TextStyle(color: Colors.black), // bodyText1 の代替
          bodyMedium: TextStyle(color: Colors.black), // bodyText2 の代替
        ),
      ),
      home: MyHomePage(title: '薬飲み忘れ防止アプリ'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  final String title;

  MyHomePage({Key? key, required this.title}) : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<Medication>> _medications = {};
  late NotificationSettings notificationSettings;

  @override
  void initState() {
    super.initState();
    _loadNotificationSettings();
  }

  void _loadNotificationSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      notificationSettings = NotificationSettings(
        isEnabled: prefs.getBool('notificationsEnabled') ?? true,
        minutesBefore: prefs.getInt('notificationMinutesBefore') ?? 30,
      );
    });
  }

  /// 複数の薬をまとめて削除する
  void deleteMedications(List<Medication> meds) {
    setState(() {
      for (var medication in meds) {
        // 通知をキャンセル
        _cancelAllNotificationsForMedication(medication);

        // _medications から削除
        _medications.forEach((date, medicationList) {
          medicationList.removeWhere((m) => m == medication);
        });
      }
      // 空になった日付キーを削除
      _medications.removeWhere((key, value) => value.isEmpty);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: Icon(Icons.list),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MedicationListPage(
                    medications: _medications,
                    onDeleteMedications: deleteMedications, // コールバックを渡す
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      NotificationSettingsPage(settings: notificationSettings),
                ),
              );
              if (result != null) {
                setState(() {
                  notificationSettings = result;
                });
                _rescheduleAllNotifications();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            calendarFormat: _calendarFormat,
            availableCalendarFormats: const {
              CalendarFormat.month: '月',
            },
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              if (!isSameDay(_selectedDay, selectedDay)) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
              }
            },
            onFormatChanged: (format) {
              setState(() {
                _calendarFormat = format;
              });
            },
            onPageChanged: (focusedDay) {
              _focusedDay = focusedDay;
            },
            eventLoader: (day) {
              return _medications[DateTime(day.year, day.month, day.day)] ?? [];
            },
          ),
          Expanded(
            child: _buildMedicationList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addMedication,
        child: Icon(Icons.add),
      ),
    );
  }

  Widget _buildMedicationList() {
    if (_selectedDay == null) {
      return Center(child: Text('日付を選択してください'));
    }

    DateTime selectedDate =
        DateTime(_selectedDay!.year, _selectedDay!.month, _selectedDay!.day);
    List<Medication> medicationsForDay = _medications[selectedDate] ?? [];

    if (medicationsForDay.isEmpty) {
      return Center(child: Text('この日の薬はありません'));
    }

    return ListView.builder(
      itemCount: medicationsForDay.length,
      itemBuilder: (context, index) {
        return ListTile(
          title: Text(medicationsForDay[index].name),
          subtitle:
              Text('服用時間: ${medicationsForDay[index].time.format(context)}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.edit),
                onPressed: () => _editMedication(selectedDate, index),
              ),
              IconButton(
                icon: Icon(Icons.delete),
                onPressed: () => _deleteMedication(selectedDate, index),
              ),
              IconButton(
                icon: Icon(Icons.check),
                onPressed: () => _markAsTaken(selectedDate, index),
              ),
            ],
          ),
        );
      },
    );
  }

  void _addMedication() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AddMedicationPage()),
    );
    if (result != null) {
      setState(() {
        _addMedicationToList(result);
      });
      _scheduleNotification(result);
    }
  }

  void _editMedication(DateTime date, int index) async {
    final medication = _medications[date]![index];
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddMedicationPage(medication: medication),
      ),
    );
    if (result != null) {
      setState(() {
        _cancelAllNotificationsForMedication(medication);
        _deleteMedicationFromList(date, index);
        _addMedicationToList(result);
      });
      _scheduleNotification(result);
    }
  }

  void _deleteMedication(DateTime date, int index) {
    setState(() {
      _deleteMedicationFromList(date, index);
    });
  }

  void _addMedicationToList(Medication medication) {
    DateTime currentDate = medication.date;
    while (currentDate.isBefore(medication.endDate ?? DateTime(2101))) {
      DateTime dateKey =
          DateTime(currentDate.year, currentDate.month, currentDate.day);
      if (_medications[dateKey] == null) {
        _medications[dateKey] = [];
      }
      _medications[dateKey]!.add(medication);

      switch (medication.repeatOption) {
        case RepeatOption.once:
          return;
        case RepeatOption.daily:
          currentDate = currentDate.add(Duration(days: 1));
          break;
        case RepeatOption.weekly:
          currentDate = currentDate.add(Duration(days: 7));
          break;
        case RepeatOption.custom:
          currentDate = currentDate.add(Duration(days: 1));
          break;
      }
    }
  }

  void _deleteMedicationFromList(DateTime date, int index) {
    final medication = _medications[date]![index];
    _medications[date]!.removeAt(index);
    if (_medications[date]!.isEmpty) {
      _medications.remove(date);
    }
    _cancelAllNotificationsForMedication(medication);
  }

  void _cancelAllNotificationsForMedication(Medication medication) {
    final now = DateTime.now();
    DateTime currentDate = medication.date;
    while (currentDate.isBefore(medication.endDate ?? DateTime(2101))) {
      flutterLocalNotificationsPlugin
          .cancel(medication.hashCode + currentDate.millisecondsSinceEpoch);

      switch (medication.repeatOption) {
        case RepeatOption.once:
          return;
        case RepeatOption.daily:
          currentDate = currentDate.add(Duration(days: 1));
          break;
        case RepeatOption.weekly:
          currentDate = currentDate.add(Duration(days: 7));
          break;
        case RepeatOption.custom:
          currentDate = currentDate.add(Duration(days: 1));
          if (currentDate.isAfter(medication.endDate!)) {
            return;
          }
          break;
      }
      if (currentDate.isBefore(now)) {
        continue;
      }
    }
  }

  Future<void> _scheduleNotification(Medication medication) async {
    if (!notificationSettings.isEnabled) return;

    DateTime currentDate = medication.date;
    final now = DateTime.now();
    while (currentDate.isBefore(medication.endDate ?? DateTime(2101))) {
      var scheduledNotificationDateTime = tz.TZDateTime.from(
        DateTime(
          currentDate.year,
          currentDate.month,
          currentDate.day,
          medication.time.hour,
          medication.time.minute,
        ),
        tz.local,
      ).subtract(Duration(minutes: notificationSettings.minutesBefore));

      if (scheduledNotificationDateTime.isAfter(now)) {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          medication.hashCode + currentDate.millisecondsSinceEpoch,
          '薬の時間です',
          '${medication.name}を飲む時間です',
          scheduledNotificationDateTime,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'medication_channel',
              'Medications',
              channelDescription: 'Medication reminders',
              importance: Importance.max,
              priority: Priority.high,
            ),
            iOS: IOSNotificationDetails(),
          ),
          androidAllowWhileIdle: true,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }

      switch (medication.repeatOption) {
        case RepeatOption.once:
          return;
        case RepeatOption.daily:
          currentDate = currentDate.add(Duration(days: 1));
          break;
        case RepeatOption.weekly:
          currentDate = currentDate.add(Duration(days: 7));
          break;
        case RepeatOption.custom:
          currentDate = currentDate.add(Duration(days: 1));
          if (currentDate.isAfter(medication.endDate!)) {
            return;
          }
          break;
      }
    }
  }

  void _markAsTaken(DateTime date, int index) {
    setState(() {
      _medications[date]?.removeAt(index);
      if (_medications[date]?.isEmpty ?? false) {
        _medications.remove(date);
      }
    });
    // TODO: 通知をキャンセルする処理を追加する
  }

  void _rescheduleAllNotifications() {
    _medications.values.expand((i) => i).forEach(_scheduleNotification);
  }
}

class Medication {
  String name;
  DateTime date;
  TimeOfDay time;
  RepeatOption repeatOption;
  DateTime? endDate;

  Medication({
    required this.name,
    required this.date,
    required this.time,
    required this.repeatOption,
    this.endDate,
  });
}

enum RepeatOption { once, daily, weekly, custom }

class AddMedicationPage extends StatefulWidget {
  final Medication? medication;

  AddMedicationPage({this.medication});

  @override
  _AddMedicationPageState createState() => _AddMedicationPageState();
}

class _AddMedicationPageState extends State<AddMedicationPage> {
  late TextEditingController nameController;
  late DateTime selectedDate;
  late TimeOfDay selectedTime;
  late RepeatOption repeatOption;
  DateTime? endDate;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.medication?.name ?? '');
    selectedDate = widget.medication?.date ?? DateTime.now();
    selectedTime = widget.medication?.time ?? TimeOfDay.now();
    repeatOption = widget.medication?.repeatOption ?? RepeatOption.once;
    endDate = widget.medication?.endDate;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.medication == null ? '薬を追加' : '薬を編集'),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: nameController,
              decoration: InputDecoration(labelText: '薬の名前'),
            ),
            SizedBox(height: 20),
            Text('日付: ${selectedDate.toString().split(' ')[0]}'),
            ElevatedButton(
              child: Text('日付を選択'),
              onPressed: () async {
                final DateTime? picked = await showDatePicker(
                  context: context,
                  initialDate: selectedDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2101),
                );
                if (picked != null && picked != selectedDate) {
                  setState(() {
                    selectedDate = picked;
                  });
                }
              },
            ),
            SizedBox(height: 20),
            Text('時間: ${selectedTime.format(context)}'),
            ElevatedButton(
              child: Text('時間を選択'),
              onPressed: () async {
                final TimeOfDay? time = await showTimePicker(
                  context: context,
                  initialTime: selectedTime,
                );
                if (time != null) {
                  setState(() {
                    selectedTime = time;
                  });
                }
              },
            ),
            SizedBox(height: 20),
            Text('繰り返し:'),
            DropdownButton<RepeatOption>(
              value: repeatOption,
              onChanged: (RepeatOption? newValue) {
                setState(() {
                  repeatOption = newValue!;
                  if (repeatOption != RepeatOption.custom) {
                    // カスタム以外は終了日をクリア
                    endDate = null;
                  }
                });
              },
              items: RepeatOption.values.map((RepeatOption option) {
                return DropdownMenuItem<RepeatOption>(
                  value: option,
                  child: Text(_getRepeatOptionText(option)),
                );
              }).toList(),
            ),
            if (repeatOption == RepeatOption.custom) ...[
              SizedBox(height: 20),
              Text('終了日: ${endDate?.toString().split(' ')[0] ?? '未設定'}'),
              ElevatedButton(
                child: Text('終了日を選択'),
                onPressed: () async {
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: endDate ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2101),
                  );
                  if (picked != null) {
                    setState(() {
                      endDate = picked;
                    });
                  }
                },
              ),
            ],
            SizedBox(height: 20),
            ElevatedButton(
              child: Text('保存'),
              onPressed: () {
                Navigator.pop(
                  context,
                  Medication(
                    name: nameController.text,
                    date: selectedDate,
                    time: selectedTime,
                    repeatOption: repeatOption,
                    endDate: endDate,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _getRepeatOptionText(RepeatOption option) {
    switch (option) {
      case RepeatOption.once:
        return '一度きり';
      case RepeatOption.daily:
        return '毎日';
      case RepeatOption.weekly:
        return '毎週';
      case RepeatOption.custom:
        return 'カスタム';
    }
  }
}

///
/// 複数選択して薬を一括削除できる一覧画面
///
class MedicationListPage extends StatefulWidget {
  final Map<DateTime, List<Medication>> medications;
  final Function(List<Medication>) onDeleteMedications;

  MedicationListPage({
    required this.medications,
    required this.onDeleteMedications,
  });

  @override
  _MedicationListPageState createState() => _MedicationListPageState();
}

class _MedicationListPageState extends State<MedicationListPage> {
  // 選択された薬を保持するSet
  Set<Medication> _selectedMedications = {};

  @override
  Widget build(BuildContext context) {
    // 全ての薬をフラットにリスト化
    List<Medication> allMedications = [];
    widget.medications.forEach((date, meds) {
      allMedications.addAll(meds);
    });

    return Scaffold(
      appBar: AppBar(
        title: Text('薬の一覧'),
        actions: [
          // 選択数が1件以上あれば、まとめて削除ボタン表示
          if (_selectedMedications.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete),
              onPressed: () {
                // MyHomePage から受け取ったコールバックを呼び出し、一括削除
                widget.onDeleteMedications(_selectedMedications.toList());

                // 画面側の選択リストをクリア
                setState(() {
                  _selectedMedications.clear();
                });
              },
            ),
        ],
      ),
      body: ListView.builder(
        itemCount: allMedications.length,
        itemBuilder: (context, index) {
          final medication = allMedications[index];
          final isSelected = _selectedMedications.contains(medication);

          return CheckboxListTile(
            title: Text(medication.name),
            subtitle: Text(
              '日付: ${medication.date.toString().split(' ')[0]}, '
              '時間: ${medication.time.format(context)}, '
              '繰り返し: ${_getRepeatOptionText(medication.repeatOption)}',
            ),
            value: isSelected,
            onChanged: (bool? newValue) {
              if (newValue == null) return;
              setState(() {
                if (newValue) {
                  _selectedMedications.add(medication);
                } else {
                  _selectedMedications.remove(medication);
                }
              });
            },
          );
        },
      ),
    );
  }

  String _getRepeatOptionText(RepeatOption option) {
    switch (option) {
      case RepeatOption.once:
        return '一度きり';
      case RepeatOption.daily:
        return '毎日';
      case RepeatOption.weekly:
        return '毎週';
      case RepeatOption.custom:
        return 'カスタム';
    }
  }
}

class NotificationSettings {
  bool isEnabled;
  int minutesBefore;

  NotificationSettings({
    required this.isEnabled,
    required this.minutesBefore,
  });
}

class NotificationSettingsPage extends StatefulWidget {
  final NotificationSettings settings;

  NotificationSettingsPage({required this.settings});

  @override
  _NotificationSettingsPageState createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  late bool isEnabled;
  late int minutesBefore;

  @override
  void initState() {
    super.initState();
    isEnabled = widget.settings.isEnabled;
    minutesBefore = widget.settings.minutesBefore;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('通知設定'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: Text('通知を有効にする'),
              value: isEnabled,
              onChanged: (value) {
                setState(() {
                  isEnabled = value;
                });
              },
            ),
            SizedBox(height: 20),
            Text('通知時間:'),
            DropdownButton<int>(
              value: minutesBefore,
              onChanged: (int? newValue) {
                setState(() {
                  minutesBefore = newValue!;
                });
              },
              items: [5, 10, 15, 30, 60].map((int value) {
                return DropdownMenuItem<int>(
                  value: value,
                  child: Text('$value分前'),
                );
              }).toList(),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              child: Text('保存'),
              onPressed: () async {
                SharedPreferences prefs = await SharedPreferences.getInstance();
                await prefs.setBool('notificationsEnabled', isEnabled);
                await prefs.setInt('notificationMinutesBefore', minutesBefore);

                Navigator.pop(
                  context,
                  NotificationSettings(
                    isEnabled: isEnabled,
                    minutesBefore: minutesBefore,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

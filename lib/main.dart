import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '薬飲み忘れ防止アプリ',
      theme: ThemeData(primarySwatch: Colors.blue),
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
                    builder: (context) =>
                        MedicationListPage(medications: _medications)),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2010, 10, 16),
            lastDay: DateTime.utc(2030, 3, 14),
            focusedDay: _focusedDay,
            calendarFormat: _calendarFormat,
            selectedDayPredicate: (day) {
              return isSameDay(_selectedDay, day);
            },
            onDaySelected: (selectedDay, focusedDay) {
              if (!isSameDay(_selectedDay, selectedDay)) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
              }
            },
            onFormatChanged: (format) {
              if (_calendarFormat != format) {
                setState(() {
                  _calendarFormat = format;
                });
              }
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
    List<Medication> medicationsForDay = _medications.entries
        .where((entry) => isSameDay(entry.key, selectedDate))
        .expand((entry) => entry.value)
        .toList();

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
          trailing: IconButton(
            icon: Icon(Icons.check),
            onPressed: () => _markAsTaken(index),
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
        DateTime dateKey =
            DateTime(result.date.year, result.date.month, result.date.day);
        if (_medications[dateKey] == null) {
          _medications[dateKey] = [];
        }
        _medications[dateKey]!.add(result);
      });
    }
  }

  void _markAsTaken(int index) {
    // TODO: 服用済みとしてマークする処理を実装
    print('薬を服用済みとしてマークしました');
  }
}

class AddMedicationPage extends StatefulWidget {
  @override
  _AddMedicationPageState createState() => _AddMedicationPageState();
}

class _AddMedicationPageState extends State<AddMedicationPage> {
  final nameController = TextEditingController();
  DateTime selectedDate = DateTime.now();
  TimeOfDay selectedTime = TimeOfDay.now();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('薬を追加')),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
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
            ElevatedButton(
              child: Text('保存'),
              onPressed: () {
                Navigator.pop(
                  context,
                  Medication(
                    name: nameController.text,
                    date: selectedDate,
                    time: selectedTime,
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

class Medication {
  String name;
  DateTime date;
  TimeOfDay time;

  Medication({required this.name, required this.date, required this.time});
}

class MedicationListPage extends StatelessWidget {
  final Map<DateTime, List<Medication>> medications;

  MedicationListPage({required this.medications});

  @override
  Widget build(BuildContext context) {
    List<Medication> allMedications = [];
    medications.forEach((date, meds) {
      allMedications.addAll(meds);
    });

    return Scaffold(
      appBar: AppBar(title: Text('薬の一覧')),
      body: ListView.builder(
        itemCount: allMedications.length,
        itemBuilder: (context, index) {
          return ListTile(
            title: Text(allMedications[index].name),
            subtitle: Text(
                '日付: ${allMedications[index].date.toString().split(' ')[0]}, '
                '時間: ${allMedications[index].time.format(context)}'),
          );
        },
      ),
    );
  }
}

# Performance Optimization Guide - Flutter App

## Masalah: Aplikasi Patah-Patah Saat Scroll

### Penyebab Umum:
1. ❌ Widget rebuild terlalu sering
2. ❌ Heavy operations di build method
3. ❌ Images tidak di-cache
4. ❌ ListView tidak efficient
5. ❌ Terlalu banyak print statements
6. ❌ Tidak pakai const widgets

---

## SOLUSI 1: Optimize Images (PALING PENTING) 🔥

### Problem
NetworkImage load ulang setiap rebuild, causing stuttering.

### Solution: Add Cached Network Image

**Install package:**
```yaml
# pubspec.yaml
dependencies:
  cached_network_image: ^3.3.1
```

**Usage:**
```dart
// BEFORE (Slow)
CircleAvatar(
  backgroundImage: NetworkImage(avatarUrl),
)

// AFTER (Fast)
import 'package:cached_network_image/cached_network_image.dart';

CircleAvatar(
  backgroundImage: CachedNetworkImageProvider(avatarUrl),
)
```

**Benefits:**
- ✅ Cache images di disk
- ✅ Tidak reload setiap rebuild
- ✅ Placeholder saat loading
- ✅ Error handling built-in

---

## SOLUSI 2: Remove Debug Print Statements

### Problem
Print statements di production mode memperlambat app.

### Solution: Use kDebugMode

**Find & Replace:**
```dart
// BEFORE (Slow)
print('Loading data...');

// AFTER (Fast)
import 'package:flutter/foundation.dart';

if (kDebugMode) {
  print('Loading data...');
}
```

**Or create helper:**
```dart
// lib/core/utils/debug_print.dart
import 'package:flutter/foundation.dart';

void debugLog(String message) {
  if (kDebugMode) {
    print(message);
  }
}

// Usage
debugLog('Loading data...');
```

---

## SOLUSI 3: Use Const Widgets

### Problem
Non-const widgets rebuild unnecessarily.

### Solution: Add const keyword

**Example:**
```dart
// BEFORE (Rebuilds every time)
Text('Hello')
SizedBox(height: 16)
Icon(Icons.home)

// AFTER (Never rebuilds)
const Text('Hello')
const SizedBox(height: 16)
const Icon(Icons.home)
```

**Rule:** Jika widget tidak berubah, tambahkan `const`.

---

## SOLUSI 4: Optimize ListView

### Problem
ListView.builder rebuild semua items saat scroll.

### Solution: Use proper itemExtent & cacheExtent

```dart
// BEFORE (Slow)
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) => ItemWidget(items[index]),
)

// AFTER (Fast)
ListView.builder(
  itemCount: items.length,
  itemExtent: 80, // Fixed height per item
  cacheExtent: 500, // Cache 500px ahead
  physics: const BouncingScrollPhysics(), // Smooth physics
  itemBuilder: (context, index) => ItemWidget(items[index]),
)
```

---

## SOLUSI 5: Avoid Heavy Operations in build()

### Problem
Expensive operations di build() method.

### Solution: Move to initState or use memo

```dart
// BEFORE (Slow - runs every rebuild)
@override
Widget build(BuildContext context) {
  final filteredData = data.where((item) => item.active).toList();
  final sortedData = filteredData..sort((a, b) => a.name.compareTo(b.name));
  
  return ListView(children: sortedData.map((item) => ItemWidget(item)).toList());
}

// AFTER (Fast - runs once)
List<Item> _processedData = [];

@override
void initState() {
  super.initState();
  _processData();
}

void _processData() {
  _processedData = data.where((item) => item.active).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
}

@override
Widget build(BuildContext context) {
  return ListView(children: _processedData.map((item) => ItemWidget(item)).toList());
}
```

---

## SOLUSI 6: Use RepaintBoundary

### Problem
Complex widgets cause entire screen to repaint.

### Solution: Wrap with RepaintBoundary

```dart
// Wrap expensive widgets
RepaintBoundary(
  child: ComplexChartWidget(),
)

RepaintBoundary(
  child: AnimatedWidget(),
)
```

---

## SOLUSI 7: Optimize State Management

### Problem
setState() rebuilds entire widget tree.

### Solution: Use smaller setState scope

```dart
// BEFORE (Rebuilds everything)
class MyPage extends StatefulWidget {
  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  int counter = 0;
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ExpensiveWidget1(),
        ExpensiveWidget2(),
        Text('$counter'), // Only this needs update
        ElevatedButton(
          onPressed: () => setState(() => counter++),
          child: Text('Increment'),
        ),
      ],
    );
  }
}

// AFTER (Only rebuilds counter)
class MyPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ExpensiveWidget1(),
        ExpensiveWidget2(),
        _CounterWidget(), // Isolated state
      ],
    );
  }
}

class _CounterWidget extends StatefulWidget {
  @override
  State<_CounterWidget> createState() => _CounterWidgetState();
}

class _CounterWidgetState extends State<_CounterWidget> {
  int counter = 0;
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$counter'),
        ElevatedButton(
          onPressed: () => setState(() => counter++),
          child: Text('Increment'),
        ),
      ],
    );
  }
}
```

---

## SOLUSI 8: Enable Release Mode Optimizations

### Build Release APK
```bash
# Build release APK (optimized)
flutter build apk --release

# NOT debug APK (slow)
flutter build apk --debug
```

### Release Mode Benefits:
- ✅ Tree shaking (remove unused code)
- ✅ Minification
- ✅ Obfuscation
- ✅ No debug overhead
- ✅ AOT compilation (faster)

---

## SOLUSI 9: Profile Your App

### Use Flutter DevTools
```bash
flutter run --profile
# Then open DevTools to see performance
```

### Check for:
- 🔍 Frame rendering time (should be < 16ms for 60fps)
- 🔍 Widget rebuild count
- 🔍 Memory usage
- 🔍 Network requests

---

## SOLUSI 10: Lazy Load Data

### Problem
Load all data at once.

### Solution: Pagination

```dart
class MyList extends StatefulWidget {
  @override
  State<MyList> createState() => _MyListState();
}

class _MyListState extends State<MyList> {
  List<Item> items = [];
  int page = 0;
  bool isLoading = false;
  
  @override
  void initState() {
    super.initState();
    _loadMore();
  }
  
  Future<void> _loadMore() async {
    if (isLoading) return;
    
    setState(() => isLoading = true);
    
    final newItems = await fetchItems(page: page, limit: 20);
    
    setState(() {
      items.addAll(newItems);
      page++;
      isLoading = false;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: items.length + 1,
      itemBuilder: (context, index) {
        if (index == items.length) {
          // Load more trigger
          if (!isLoading) _loadMore();
          return Center(child: CircularProgressIndicator());
        }
        return ItemWidget(items[index]);
      },
    );
  }
}
```

---

## Quick Wins Checklist

Prioritas tinggi untuk hasil cepat:

### 1. ✅ Install cached_network_image
```bash
flutter pub add cached_network_image
```

### 2. ✅ Replace all NetworkImage
```dart
// Find: NetworkImage(
// Replace: CachedNetworkImageProvider(
```

### 3. ✅ Wrap print statements
```dart
// Find: print(
// Replace: if (kDebugMode) print(
```

### 4. ✅ Add const to static widgets
```dart
// Add const wherever possible
const Text('Hello')
const SizedBox(height: 16)
const Icon(Icons.home)
```

### 5. ✅ Build release APK
```bash
flutter build apk --release
```

---

## Expected Results

After optimization:
- ✅ Smooth 60fps scrolling
- ✅ Faster app startup
- ✅ Lower memory usage
- ✅ Better battery life
- ✅ Smaller APK size

---

## Monitoring Performance

### Check FPS in DevTools
```bash
flutter run --profile
# Open DevTools → Performance tab
# Look for frame rendering time
```

### Target Metrics:
- **Frame time**: < 16ms (60fps)
- **Memory**: < 100MB for simple screens
- **APK size**: < 50MB
- **Startup time**: < 3 seconds

---

## Common Mistakes to Avoid

❌ **DON'T**:
- Use `ListView(children: [...])` for long lists
- Put heavy operations in build()
- Use `setState()` for entire page
- Load all data at once
- Use debug mode for testing performance
- Forget to add const
- Use print() in production

✅ **DO**:
- Use `ListView.builder()` with itemExtent
- Move operations to initState()
- Use smaller state scopes
- Implement pagination
- Test in release mode
- Add const everywhere possible
- Use conditional debug prints

---

## Next Steps

1. Install `cached_network_image` package
2. Replace all NetworkImage usage
3. Add const to static widgets
4. Wrap debug prints with kDebugMode
5. Build release APK and test
6. Profile with DevTools if still slow
7. Implement pagination for large lists

Setelah implementasi, aplikasi akan jauh lebih smooth! 🚀

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bs_admin/home.dart';

class MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return MockHttpClient();
  }
}

class MockHttpClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    print('MockHttpClient noSuchMethod: ${invocation.memberName}');
    Uri? uri;
    for (var arg in invocation.positionalArguments) {
      if (arg is Uri) {
        uri = arg;
        break;
      }
    }
    if (uri != null) {
      return Future.value(MockHttpClientRequest(uri));
    }
    return Future.value(null);
  }
}

class MockHttpClientRequest implements HttpClientRequest {
  final Uri url;
  MockHttpClientRequest(this.url);

  @override
  final HttpHeaders headers = MockHttpHeaders();

  @override
  final List<Cookie> cookies = [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    print('MockHttpClientRequest noSuchMethod: ${invocation.memberName}');
    if (invocation.memberName == #close) {
      String responseBody = '{"docs": []}';
      if (url.path.contains('branches')) {
        responseBody = '{"docs": [{"id": "b1", "name": "Branch 1"}]}';
      } else if (url.path.contains('billings')) {
        responseBody = '{"docs": [{"status": "completed", "branch": "b1", "grandTotal": 12500.50, "paymentMethod": "cash"}]}';
      } else if (url.path.contains('expenses')) {
        responseBody = '{"docs": [{"branch": "b1", "amount": 1500.0}]}';
      } else if (url.path.contains('closing-entries')) {
        responseBody = '{"docs": []}';
      }
      return Future.value(MockHttpClientResponse(responseBody));
    }
    return Future.value(null);
  }
}

class MockHttpHeaders implements HttpHeaders {
  @override
  List<String>? operator [](String name) => [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    print('MockHttpHeaders noSuchMethod: ${invocation.memberName}');
    return null;
  }
}

class MockHttpClientResponse extends Stream<List<int>> implements HttpClientResponse {
  final String body;
  MockHttpClientResponse(this.body);

  @override
  int get statusCode => 200;

  @override
  String get reasonPhrase => 'OK';

  @override
  int get contentLength => body.length;

  @override
  final HttpHeaders headers = MockHttpHeaders();

  @override
  final List<Cookie> cookies = [];

  @override
  final bool persistentConnection = false;

  @override
  final bool isRedirect = false;

  @override
  final List<RedirectInfo> redirects = [];

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([utf8.encode(body)]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    print('MockHttpClientResponse noSuchMethod: ${invocation.memberName}');
    return null;
  }
}

void main() {
  setUp(() {
    HttpOverrides.global = MockHttpOverrides();
  });

  tearDown(() {
    HttpOverrides.global = null;
  });

  testWidgets('HomePage loads mock data and renders correctly', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'token': 'mock-token'});

    await tester.pumpWidget(
      const MaterialApp(
        home: HomePage(),
      ),
    );

    // Initial build shows loading
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Wait for the async fetch to finish and trigger rebuild
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify "Total balance" is displayed
    expect(find.text('Total balance'), findsOneWidget);

    // Verify grand total amount is displayed formatted (12,500.50)
    expect(find.textContaining('12,500.50'), findsOneWidget);

    // Verify mockup grid actions are rendered
    expect(find.text('BILLING'), findsOneWidget);
    expect(find.text('EXPENSES'), findsOneWidget);
    expect(find.text('STOCK'), findsOneWidget);
    expect(find.text('RETURN'), findsOneWidget);

    // Let any pending Future.delayed timers complete before widget disposal
    await tester.pump(const Duration(seconds: 1));
  });
}

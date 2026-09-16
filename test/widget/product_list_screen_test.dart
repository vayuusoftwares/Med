import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medsafelifescience/product_list_screen.dart';

class _MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _MockHttpClient();
}

class _MockHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async => _MockHttpClientRequest();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockHttpClientRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _MockHttpHeaders();
  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();
  @override
  Future<void> addStream(Stream<List<int>> stream) async {}
  @override
  void add(List<int> data) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockHttpHeaders implements HttpHeaders {
  @override
  void forEach(void Function(String name, List<String> values) action) {
    action('content-type', ['image/svg+xml']);
  }
  @override
  List<String>? operator [](String name) {
    if (name.toLowerCase() == 'content-type') return ['image/svg+xml'];
    return null;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockHttpClientResponse extends Stream<List<int>> implements HttpClientResponse {
  final List<int> _body = utf8.encode('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"></svg>');
  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  int get statusCode => 200;
  @override
  bool get isRedirect => false;
  @override
  List<RedirectInfo> get redirects => const [];
  @override
  bool get persistentConnection => false;
  @override
  String get reasonPhrase => 'OK';
  @override
  int get contentLength => _body.length;
  @override
  HttpClientResponseCompressionState get compressionState => HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return Stream.value(_body).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Widget _wrapList({String categoryName = 'Gastrology'}) => MaterialApp(
      home: ProductListScreen(categoryName: categoryName),
    );

void main() {
  setUpAll(() {
    HttpOverrides.global = _MockHttpOverrides();
  });
  testWidgets('renders ProductListScreen with category header', (tester) async {
    await tester.pumpWidget(_wrapList(categoryName: 'Gastrology'));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Gastrology'), findsWidgets);
    expect(find.widgetWithText(TextField, 'Search for medicines...'), findsOneWidget);
  });

  testWidgets('search filters product list', (tester) async {
    await tester.pumpWidget(_wrapList(categoryName: 'Gastrology'));
    await tester.pump(const Duration(milliseconds: 600));

    final searchField = find.widgetWithText(TextField, 'Search for medicines...');
    await tester.enterText(searchField, 'NonExistentProductXYZ');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('No medicines found'), findsOneWidget);
  });

  testWidgets('clearing search restores product list', (tester) async {
    await tester.pumpWidget(_wrapList(categoryName: 'Gastrology'));
    await tester.pump(const Duration(milliseconds: 600));

    final searchField = find.widgetWithText(TextField, 'Search for medicines...');
    await tester.enterText(searchField, 'NonExistentProductXYZ');
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(searchField, '');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('No medicines found'), findsNothing);
  });
}

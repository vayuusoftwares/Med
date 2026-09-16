import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medsafelifescience/product_catalog_screen.dart';

Widget _wrapCatalog({int initialCategory = 2}) => MaterialApp(
      home: ProductCatalogScreen(initialCategory: initialCategory),
    );

void main() {
  testWidgets('renders ProductCatalogScreen with category titles', (tester) async {
    await tester.pumpWidget(_wrapCatalog());
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Product Catalog'), findsOneWidget);
    expect(find.textContaining('Explore our pharmaceutical'), findsOneWidget);
  });

  testWidgets('renders page indicator dots', (tester) async {
    await tester.pumpWidget(_wrapCatalog());
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(PageView), findsOneWidget);
  });

  testWidgets('swiping page controller changes category', (tester) async {
    await tester.pumpWidget(_wrapCatalog());
    await tester.pump(const Duration(milliseconds: 600));

    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(PageView), findsOneWidget);
  });
}

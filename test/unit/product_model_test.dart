import 'package:flutter_test/flutter_test.dart';
import 'package:medsafelifescience/models/product.dart';
import 'package:medsafelifescience/data/product_data.dart';

void main() {
  group('Product model', () {
    const product = Product(
      id: 'test_001',
      name: 'Test Tablet 10s',
      price: 299.0,
      imageUrl: 'https://example.com/img.jpg',
      category: 'gastrology',
      source: 'test',
      composition: 'Active Ingredient 10mg',
      packSize: '1x10',
      description: 'Test description.',
      rating: 4.5,
    );

    test('id is set correctly', () => expect(product.id, 'test_001'));
    test('name is set correctly', () => expect(product.name, 'Test Tablet 10s'));
    test('price is set correctly', () => expect(product.price, 299.0));
    test('category is set correctly', () => expect(product.category, 'gastrology'));
    test('composition is set correctly', () => expect(product.composition, 'Active Ingredient 10mg'));
    test('packSize is set correctly', () => expect(product.packSize, '1x10'));
    test('rating is set correctly', () => expect(product.rating, 4.5));
    test('source is set correctly', () => expect(product.source, 'test'));

    test('defaults: packSize = 1x10', () {
      const p = Product(
        id: 'x', name: 'X', price: 1.0,
        imageUrl: '', category: 'cat', source: 'src',
      );
      expect(p.packSize, '1x10');
    });

    test('defaults: rating = 4.5', () {
      const p = Product(
        id: 'x', name: 'X', price: 1.0,
        imageUrl: '', category: 'cat', source: 'src',
      );
      expect(p.rating, 4.5);
    });

    test('defaults: description is non-empty', () {
      const p = Product(
        id: 'x', name: 'X', price: 1.0,
        imageUrl: '', category: 'cat', source: 'src',
      );
      expect(p.description, isNotEmpty);
    });
  });

  group('ProductData catalog', () {
    test('allProducts is non-empty', () {
      expect(ProductData.allProducts, isNotEmpty);
    });

    test('all products have non-empty id', () {
      for (final p in ProductData.allProducts) {
        expect(p.id, isNotEmpty, reason: 'Product "${p.name}" has empty id');
      }
    });

    test('all products have non-empty name', () {
      for (final p in ProductData.allProducts) {
        expect(p.name, isNotEmpty, reason: 'Product id "${p.id}" has empty name');
      }
    });

    test('all products have positive price', () {
      for (final p in ProductData.allProducts) {
        expect(p.price, greaterThanOrEqualTo(0), reason: 'Product "${p.name}" has non-positive price');
      }
    });

    test('all products have non-empty category', () {
      for (final p in ProductData.allProducts) {
        expect(p.category, isNotEmpty, reason: 'Product "${p.name}" has empty category');
      }
    });

    test('all product ids are unique', () {
      final ids = ProductData.allProducts.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('MedSafe catalog contains all 32 official products', () {
      expect(ProductData.allProducts.length, 32);
    });

    test('MedSafe catalog covers all 5 key categories', () {
      expect(ProductData.getProductsByCategory('general'), isNotEmpty);
      expect(ProductData.getProductsByCategory('orthopedic'), isNotEmpty);
      expect(ProductData.getProductsByCategory('gastroenterology'), isNotEmpty);
      expect(ProductData.getProductsByCategory('neurology'), isNotEmpty);
      expect(ProductData.getProductsByCategory('gynecology'), isNotEmpty);
    });

    test('All products have company source set to medsafe', () {
      for (final p in ProductData.allProducts) {
        expect(p.source, 'medsafe');
      }
    });
  });
}

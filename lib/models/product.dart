class Product {
  final String id;
  final String name;
  final String genericName;
  final double price;
  final String imageUrl;
  final String category;
  final String source;
  final String composition;
  final String packSize;
  final String dosage;
  final String description;
  final String indications;
  final String brochureUrl;
  final double rating;

  const Product({
    required this.id,
    required this.name,
    this.genericName = '',
    required this.price,
    required this.imageUrl,
    required this.category,
    required this.source,
    this.composition = '',
    this.packSize = '1x10',
    this.dosage = 'As directed by the physician',
    this.description = 'Pharmaceutical grade medicine for effective treatment.',
    this.indications = '',
    this.brochureUrl = '',
    this.rating = 4.5,
  });
}

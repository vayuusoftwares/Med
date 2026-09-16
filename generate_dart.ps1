$ErrorActionPreference = 'Stop'

$ff = Get-Content 'ff_products.json' | ConvertFrom-Json
$daris = Get-Content 'daris_products.json' | ConvertFrom-Json

$allProducts = @()
$allProducts += $ff
$allProducts += $daris

$dartCode = @"
import '../models/product.dart';

class ProductData {
  static const List<Product> allProducts = [
"@

$idCounter = 1
foreach ($p in $allProducts) {
    $name = $p.name -replace "'", "\'" -replace '"', '\"'
    $cat = $p.category.ToLower()
    $price = $p.price
    $img = $p.imageUrl
    $src = $p.source

    $dartCode += @"
    Product(
      id: 'prod_$idCounter',
      name: '$name',
      price: $price,
      imageUrl: '$img',
      category: '$cat',
      source: '$src',
    ),
"@
    $idCounter++
}

$dartCode += @"
  ];

  static List<Product> getProductsByCategory(String category) {
    final searchCat = category.toLowerCase();
    // Some basic mapping if needed
    if (searchCat == 'cardiology') {
        return allProducts.where((p) => p.category == 'cardiology' || p.category == 'general').toList();
    }
    return allProducts.where((p) => p.category == searchCat).toList();
  }
}
"@

$dartCode | Out-File -FilePath "lib\data\product_data.dart" -Encoding UTF8
Write-Host "Generated lib\data\product_data.dart"

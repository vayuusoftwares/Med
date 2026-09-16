$ErrorActionPreference = 'Stop'

# Get all products (no category filter first)
$page = 1
$allProducts = @()
do {
    $url = "https://fineformulations.com/wp-json/wc/store/products?per_page=100&page=$page"
    Write-Host "Fetching page $page from: $url"
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
        $products = $response.Content | ConvertFrom-Json
        if ($null -eq $products -or $products.Count -eq 0) { break }
        Write-Host "  Got $($products.Count) products"
        foreach ($p in $products) {
            $imgUrl = ''
            if ($null -ne $p.images -and $p.images.Count -gt 0) {
                $imgUrl = $p.images[0].thumbnail
            }
            $minorUnit = 2
            if ($null -ne $p.prices.currency_minor_unit) {
                $minorUnit = [int]$p.prices.currency_minor_unit
            }
            $price = [double]$p.prices.price / [math]::Pow(10, $minorUnit)
            
            $catName = 'general'
            $permalink = $p.permalink
            if ($permalink -match 'gastrology') { $catName = 'gastrology' }
            elseif ($permalink -match 'neurology') { $catName = 'neurology' }
            elseif ($permalink -match 'orthopedic') { $catName = 'orthopedic' }
            elseif ($permalink -match 'hematology') { $catName = 'hematology' }
            elseif ($permalink -match 'gynacology') { $catName = 'gynacology' }
            elseif ($permalink -match 'cardiology') { $catName = 'cardiology' }

            $cleanName = $p.name -replace [char]0x2019, "'" -replace '&#8217;', "'" -replace '&amp;', '&' -replace '&#8211;', '-'
            
            $allProducts += [PSCustomObject]@{
                category = $catName
                name = $cleanName
                price = $price
                imageUrl = $imgUrl
                id = $p.id
                source = 'fineformulations'
            }
        }
        $page++
    } catch {
        Write-Host "Error: $_"
        break
    }
} while ($products.Count -ge 100)

# Also try fetching from each category page to get categorized data
$categoryPages = @(
    @{name='gastrology'; id=15},
    @{name='neurology'; id=16},
    @{name='orthopedic'; id=17},
    @{name='hematology'; id=18},
    @{name='gynacology'; id=19},
    @{name='cardiology'; id=20},
    @{name='general'; id=21}
)

foreach ($cat in $categoryPages) {
    $page = 1
    do {
        $url = "https://fineformulations.com/wp-json/wc/store/products?category=$($cat.id)&per_page=100&page=$page"
        Write-Host "Fetching category $($cat.name) (id=$($cat.id)) page $page"
        try {
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
            $products = $response.Content | ConvertFrom-Json
            if ($null -eq $products -or $products.Count -eq 0) { break }
            Write-Host "  Got $($products.Count) products in $($cat.name)"
            foreach ($p in $products) {
                # Check if already exists
                $existing = $allProducts | Where-Object { $_.id -eq $p.id }
                if ($null -ne $existing) {
                    # Update category
                    $existing.category = $cat.name
                    continue
                }
                $imgUrl = ''
                if ($null -ne $p.images -and $p.images.Count -gt 0) {
                    $imgUrl = $p.images[0].thumbnail
                }
                $minorUnit = 2
                if ($null -ne $p.prices.currency_minor_unit) {
                    $minorUnit = [int]$p.prices.currency_minor_unit
                }
                $price = [double]$p.prices.price / [math]::Pow(10, $minorUnit)
                $cleanName = $p.name -replace [char]0x2019, "'" -replace '&#8217;', "'" -replace '&amp;', '&' -replace '&#8211;', '-'
                $allProducts += [PSCustomObject]@{
                    category = $cat.name
                    name = $cleanName
                    price = $price
                    imageUrl = $imgUrl
                    id = $p.id
                    source = 'fineformulations'
                }
            }
            $page++
        } catch {
            Write-Host "Error fetching category $($cat.name): $_"
            break
        }
    } while ($products.Count -ge 100)
}

# Deduplicate by id
$unique = $allProducts | Sort-Object -Property id -Unique
Write-Host ""
Write-Host "Total unique products: $($unique.Count)"
Write-Host "By category:"
$unique | Group-Object category | ForEach-Object { Write-Host "  $($_.Name): $($_.Count)" }
Write-Host ""

# Output as JSON
$unique | ConvertTo-Json -Depth 5 | Out-File -FilePath "ff_products.json" -Encoding UTF8
Write-Host "Saved to ff_products.json"

# Also output in a format easy to read
foreach ($cat in ($unique | Group-Object category)) {
    Write-Host ""
    Write-Host "=== $($cat.Name) ==="
    foreach ($p in $cat.Group) {
        Write-Host "  $($p.name) | Rs.$($p.price) | $($p.imageUrl)"
    }
}

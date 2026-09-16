$ErrorActionPreference = 'Stop'

$content = Get-Content 'C:\Users\ADMIN\.gemini\antigravity\brain\f7594162-fc0a-4e99-988c-415636d91e83\.system_generated\steps\79\content.md' -Raw

$pattern = 'themestek-box-category.*?<a href="https://darisbiocare\.com/research-category/(.*?)/.*?">(.*?)</a>.*?<h3><a title="(.*?)" href=".*?">.*?<img.*?src="?(https://darisbiocare\.com/wp-content/uploads/[^"\s>]+)'

$regex = [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline)

$matches = $regex.Matches($content)

$products = @()

foreach ($match in $matches) {
    $categorySlug = $match.Groups[1].Value.Trim()
    $categoryName = $match.Groups[2].Value.Trim()
    $productName = $match.Groups[3].Value.Trim()
    $imageUrl = $match.Groups[4].Value.Trim()

    # Map categories to our app categories
    $mappedCategory = 'general'
    if ($categorySlug -match 'gastro') { $mappedCategory = 'gastrology' }
    elseif ($categorySlug -match 'nuero' -or $categorySlug -match 'neuro') { $mappedCategory = 'neurology' }
    elseif ($categorySlug -match 'ortho') { $mappedCategory = 'orthopedic' }
    elseif ($categorySlug -match 'hema') { $mappedCategory = 'hematology' }
    elseif ($categorySlug -match 'fem' -or $categorySlug -match 'gyna') { $mappedCategory = 'gynacology' }
    elseif ($categorySlug -match 'cardio') { $mappedCategory = 'cardiology' }

    $products += [PSCustomObject]@{
        category = $mappedCategory
        name = $productName -replace '&#8217;',"'" -replace '&amp;','&' -replace '&#8211;', '-'
        price = 0 # Daris doesn't seem to list prices in the portfolio list
        imageUrl = $imageUrl
        source = 'darisbiocare'
    }
}

$unique = $products | Sort-Object -Property name -Unique
$unique | ConvertTo-Json -Depth 5 | Out-File -FilePath "daris_products.json" -Encoding UTF8

Write-Host "Total unique Daris products: $($unique.Count)"
$unique | Group-Object category | ForEach-Object { Write-Host "  $($_.Name): $($_.Count)" }

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'models/product.dart';
import 'models/user_model.dart';
import 'data/product_data.dart';

class OrderNowScreen extends StatefulWidget {
  final User salesRep;

  const OrderNowScreen({super.key, required this.salesRep});

  @override
  State<OrderNowScreen> createState() => _OrderNowScreenState();
}

class _OrderNowScreenState extends State<OrderNowScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _doctorNameController = TextEditingController();
  final TextEditingController _hospitalNameController = TextEditingController();
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _offeredCostController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Product> _allProducts = [];
  final Map<String, int> _quantities = {};
  String _searchQuery = '';
  int _loadedItemCount = 15;

  static const _emeraldPrimary = Color(0xFF00A86B);
  static const _emeraldDark = Color(0xFF047857);
  static const _emeraldLight = Color(0xFFECFDF5);
  static const _bgLight = Color(0xFFF8FAFC);
  static const _cardBorder = Color(0xFFE2E8F0);
  static const _darkText = Color(0xFF0F172A);
  static const _subtext = Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    _allProducts = ProductData.allProducts;
    _offeredCostController.addListener(_updateCalculations);
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (_loadedItemCount < _allProducts.length) {
        setState(() {
          _loadedItemCount += 15;
        });
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _doctorNameController.dispose();
    _hospitalNameController.dispose();
    _mobileController.dispose();
    _offeredCostController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _updateCalculations() {
    setState(() {});
  }

  void _clearOrder() {
    setState(() {
      _doctorNameController.clear();
      _hospitalNameController.clear();
      _mobileController.clear();
      _offeredCostController.clear();
      _quantities.clear();
      _searchController.clear();
      _searchQuery = '';
      _loadedItemCount = 15;
    });
  }

  double get _subtotal {
    double total = 0;
    _quantities.forEach((id, qty) {
      final product = _allProducts.firstWhere((p) => p.id == id);
      total += (product.price * qty);
    });
    return total;
  }

  int get _totalQuantity {
    int total = 0;
    for (var qty in _quantities.values) {
      total += qty;
    }
    return total;
  }

  double get _offeredCost {
    if (_offeredCostController.text.isEmpty) return _subtotal;
    return double.tryParse(_offeredCostController.text) ?? _subtotal;
  }

  double get _offerPercentage {
    if (_subtotal == 0) return 0;
    if (_offeredCost > _subtotal) return 0;
    return ((_subtotal - _offeredCost) / _subtotal) * 100;
  }

  bool _validateOrder() {
    if (!_formKey.currentState!.validate()) return false;
    
    if (_totalQuantity == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white),
              SizedBox(width: 8),
              Text('Please add at least one product to the order.'),
            ],
          ),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return false;
    }

    if (_offeredCost > _subtotal) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error_outline_rounded, color: Colors.white),
              SizedBox(width: 8),
              Text('Offered cost cannot exceed the subtotal.'),
            ],
          ),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return false;
    }
    return true;
  }

  // ─── PDF GENERATION ────────────────────────────────────────────────────────

  Future<void> _generateAndDownloadPDF() async {
    if (!_validateOrder()) return;

    final pdf = pw.Document();
    
    // Filter selected products
    final selectedProducts = _allProducts
        .where((p) => (_quantities[p.id] ?? 0) > 0)
        .toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            _buildPdfHeader(),
            pw.SizedBox(height: 20),
            _buildPdfDoctorInfo(),
            pw.SizedBox(height: 20),
            _buildPdfTable(selectedProducts),
            pw.SizedBox(height: 20),
            _buildPdfSummary(),
            pw.SizedBox(height: 40),
            _buildPdfFooter(),
          ];
        },
      ),
    );

    // Save and layout PDF
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Order_${_doctorNameController.text.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  pw.Widget _buildPdfHeader() {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 12),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.teal, width: 2)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('MedSafe Life Science', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.teal900)),
              pw.Text('Pharmaceuticals & Healthcare Solutions', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('DOCTOR PRODUCT ORDER', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.teal700)),
              pw.Text('Date: ${DateFormat('dd-MM-yyyy').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfDoctorInfo() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Doctor Name: ${_doctorNameController.text}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('Hospital / Clinic: ${_hospitalNameController.text.isNotEmpty ? _hospitalNameController.text : 'N/A'}'),
              pw.SizedBox(height: 4),
              pw.Text('Mobile: ${_mobileController.text.isNotEmpty ? _mobileController.text : 'N/A'}'),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('Sales Rep: ${widget.salesRep.name}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('Rep Email: ${widget.salesRep.email}'),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfTable(List<Product> products) {
    return pw.TableHelper.fromTextArray(
      context: null,
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.teal),
      cellHeight: 25,
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.center,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.center,
        5: pw.Alignment.centerRight,
      },
      headers: ['Product Name', 'Composition', 'Pack Size', 'Unit Price', 'Qty', 'Total Price'],
      data: products.map((p) {
        final qty = _quantities[p.id] ?? 0;
        return [
          p.name,
          p.composition,
          p.packSize,
          'INR ${p.price.toStringAsFixed(2)}',
          qty.toString(),
          'INR ${(p.price * qty).toStringAsFixed(2)}',
        ];
      }).toList(),
    );
  }

  pw.Widget _buildPdfSummary() {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Container(
          width: 220,
          child: pw.Column(
            children: [
              _buildPdfSummaryRow('Total Quantity:', '$_totalQuantity'),
              _buildPdfSummaryRow('Subtotal:', 'INR ${_subtotal.toStringAsFixed(2)}'),
              if (_offerPercentage > 0)
                _buildPdfSummaryRow('Discount (${_offerPercentage.toStringAsFixed(1)}%):', '- INR ${(_subtotal - _offeredCost).toStringAsFixed(2)}'),
              pw.Divider(color: PdfColors.grey400),
              _buildPdfSummaryRow('Final Amount:', 'INR ${_offeredCost.toStringAsFixed(2)}', isBold: true),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _buildPdfSummaryRow(String label, String value, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 10, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      ),
    );
  }

  pw.Widget _buildPdfFooter() {
    return pw.Column(
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              children: [
                pw.Container(width: 120, height: 1, color: PdfColors.grey400),
                pw.SizedBox(height: 4),
                pw.Text('Doctor Signature', style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
            pw.Column(
              children: [
                pw.Container(width: 120, height: 1, color: PdfColors.grey400),
                pw.SizedBox(height: 4),
                pw.Text('Sales Rep Signature', style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 20),
        pw.Text('Thank you for your business! - MedSafe Life Science', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
      ],
    );
  }

  // ─── UI BUILD ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Theme(
      data: ThemeData.light().copyWith(
        scaffoldBackgroundColor: _bgLight,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _emeraldPrimary,
          primary: _emeraldPrimary,
          surface: Colors.white,
        ),
      ),
      child: Scaffold(
        backgroundColor: _bgLight,
        appBar: AppBar(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _emeraldLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.medication_rounded, color: _emeraldDark, size: 22),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Doctor Product Order',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _darkText,
                    ),
                  ),
                  Text(
                    'Generate quotation & purchase order',
                    style: TextStyle(
                      fontSize: 12,
                      color: _subtext,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ],
          ),
          backgroundColor: Colors.white,
          elevation: 0.5,
          scrolledUnderElevation: 1,
          iconTheme: const IconThemeData(color: _darkText),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (isDesktop)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 3, child: _buildHeaderCard(isDesktop)),
                              const SizedBox(width: 20),
                              Expanded(flex: 2, child: _buildOrderSummaryCard()),
                            ],
                          )
                        else ...[
                          _buildHeaderCard(isDesktop),
                          const SizedBox(height: 20),
                        ],
                        const SizedBox(height: 20),
                        _buildProductSelectionCard(),
                        if (!isDesktop) ...[
                          const SizedBox(height: 20),
                          _buildOrderSummaryCard(),
                        ],
                        const SizedBox(height: 24),
                        _buildActionButtons(),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── CARDS ─────────────────────────────────────────────────────────────────

  Widget _buildHeaderCard(bool isDesktop) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCardTitle(
            icon: Icons.person_pin_rounded,
            title: 'Doctor Information',
            subtitle: 'Enter target doctor information for order PDF',
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final useTwoColumns = constraints.maxWidth > 500;
              return Column(
                children: [
                  if (useTwoColumns)
                    Row(
                      children: [
                        Expanded(
                          child: _buildInputField(
                            controller: _doctorNameController,
                            label: 'Doctor Name *',
                            hint: 'e.g. Dr. Ramesh Kumar',
                            icon: Icons.person_outline_rounded,
                            validator: (v) => v == null || v.isEmpty ? 'Doctor Name required' : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildInputField(
                            controller: _mobileController,
                            label: 'Mobile Number',
                            hint: '10-digit mobile number',
                            icon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                          ),
                        ),
                      ],
                    )
                  else ...[
                    _buildInputField(
                      controller: _doctorNameController,
                      label: 'Doctor Name *',
                      hint: 'e.g. Dr. Ramesh Kumar',
                      icon: Icons.person_outline_rounded,
                      validator: (v) => v == null || v.isEmpty ? 'Doctor Name required' : null,
                    ),
                    const SizedBox(height: 16),
                    _buildInputField(
                      controller: _mobileController,
                      label: 'Mobile Number',
                      hint: '10-digit mobile number',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                    ),
                  ],
                  const SizedBox(height: 16),
                  _buildInputField(
                    controller: _hospitalNameController,
                    label: 'Hospital / Clinic Name',
                    hint: 'e.g. Apollo Health Centre',
                    icon: Icons.local_hospital_outlined,
                  ),
                  const SizedBox(height: 16),
                  if (useTwoColumns)
                    Row(
                      children: [
                        Expanded(
                          child: _buildInputField(
                            initialValue: DateFormat('dd-MM-yyyy').format(DateTime.now()),
                            label: 'Order Date',
                            icon: Icons.calendar_today_outlined,
                            readOnly: true,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildInputField(
                            initialValue: widget.salesRep.name,
                            label: 'Sales Representative',
                            icon: Icons.badge_outlined,
                            readOnly: true,
                          ),
                        ),
                      ],
                    )
                  else ...[
                    _buildInputField(
                      initialValue: DateFormat('dd-MM-yyyy').format(DateTime.now()),
                      label: 'Order Date',
                      icon: Icons.calendar_today_outlined,
                      readOnly: true,
                    ),
                    const SizedBox(height: 16),
                    _buildInputField(
                      initialValue: widget.salesRep.name,
                      label: 'Sales Representative',
                      icon: Icons.badge_outlined,
                      readOnly: true,
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProductSelectionCard() {
    final filteredProducts = _searchQuery.isEmpty
        ? <Product>[]
        : _allProducts
            .where((p) =>
                p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                p.composition.toLowerCase().contains(_searchQuery.toLowerCase()))
            .take(10)
            .toList();

    final selectedProducts = _allProducts.where((p) => (_quantities[p.id] ?? 0) > 0).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCardTitle(
            icon: Icons.add_shopping_cart_rounded,
            title: 'Add Medicines & Products',
            subtitle: 'Search and select products to build quotation table',
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _searchController,
            style: const TextStyle(color: _darkText, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Type medicine name or composition...',
              hintStyle: const TextStyle(color: _subtext, fontSize: 14),
              prefixIcon: const Icon(Icons.search_rounded, color: _emeraldPrimary),
              filled: true,
              fillColor: _bgLight,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _cardBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _cardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _emeraldPrimary, width: 2),
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.cancel_rounded, color: _subtext),
                      onPressed: () {
                        setState(() {
                          _searchController.clear();
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),

          if (filteredProducts.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 10),
              constraints: const BoxConstraints(maxHeight: 280),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _emeraldPrimary.withOpacity(0.4), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: _emeraldPrimary.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: filteredProducts.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: _cardBorder),
                itemBuilder: (context, index) {
                  final p = filteredProducts[index];
                  final isAlreadyAdded = (_quantities[p.id] ?? 0) > 0;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    title: Text(
                      p.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: _darkText, fontSize: 14),
                    ),
                    subtitle: Text(
                      '${p.composition} • ${p.packSize}',
                      style: const TextStyle(color: _subtext, fontSize: 12),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isAlreadyAdded ? _emeraldLight : _emeraldPrimary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '₹${p.price.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: isAlreadyAdded ? _emeraldDark : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            isAlreadyAdded ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                            color: isAlreadyAdded ? _emeraldDark : Colors.white,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                    onTap: () {
                      setState(() {
                        _quantities[p.id] = (_quantities[p.id] ?? 0) + 1;
                        _searchController.clear();
                        _searchQuery = '';
                        FocusScope.of(context).unfocus();
                      });
                    },
                  );
                },
              ),
            ),

          if (selectedProducts.isEmpty) ...[
            const SizedBox(height: 28),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _emeraldLight,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.shopping_bag_outlined, color: _emeraldDark, size: 36),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No products added yet',
                      style: TextStyle(fontWeight: FontWeight.bold, color: _darkText, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Use the search bar above to select products for this doctor order.',
                      style: TextStyle(color: _subtext, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Selected Order Items',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _darkText),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _emeraldLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${selectedProducts.length} Products',
                    style: const TextStyle(color: _emeraldDark, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _cardBorder),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(_emeraldLight),
                  dataRowMinHeight: 56,
                  dataRowMaxHeight: 64,
                  horizontalMargin: 16,
                  columnSpacing: 24,
                  columns: const [
                    DataColumn(label: Text('Product Name', style: TextStyle(fontWeight: FontWeight.bold, color: _emeraldDark))),
                    DataColumn(label: Text('Composition', style: TextStyle(fontWeight: FontWeight.bold, color: _emeraldDark))),
                    DataColumn(label: Text('Pack Size', style: TextStyle(fontWeight: FontWeight.bold, color: _emeraldDark))),
                    DataColumn(label: Text('Unit Price', style: TextStyle(fontWeight: FontWeight.bold, color: _emeraldDark))),
                    DataColumn(label: Text('Quantity', style: TextStyle(fontWeight: FontWeight.bold, color: _emeraldDark))),
                    DataColumn(label: Text('Total Price', style: TextStyle(fontWeight: FontWeight.bold, color: _emeraldDark))),
                    DataColumn(label: Text('Action', style: TextStyle(fontWeight: FontWeight.bold, color: _emeraldDark))),
                  ],
                  rows: selectedProducts.map((p) {
                    final qty = _quantities[p.id] ?? 0;
                    return DataRow(
                      cells: [
                        DataCell(
                          SizedBox(
                            width: 180,
                            child: Text(
                              p.name,
                              style: const TextStyle(fontWeight: FontWeight.w600, color: _darkText),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 160,
                            child: Text(
                              p.composition,
                              style: const TextStyle(color: _subtext, fontSize: 13),
                            ),
                          ),
                        ),
                        DataCell(Text(p.packSize, style: const TextStyle(color: _darkText, fontSize: 13))),
                        DataCell(Text('₹${p.price.toStringAsFixed(2)}', style: const TextStyle(color: _darkText, fontWeight: FontWeight.w500))),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: () {
                                  if (qty > 1) {
                                    setState(() => _quantities[p.id] = qty - 1);
                                  } else {
                                    setState(() => _quantities.remove(p.id));
                                  }
                                },
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: _cardBorder),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(Icons.remove, size: 14, color: _darkText),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: Text(
                                  '$qty',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _darkText),
                                ),
                              ),
                              InkWell(
                                onTap: () {
                                  setState(() => _quantities[p.id] = qty + 1);
                                },
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: _emeraldLight,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(Icons.add, size: 14, color: _emeraldDark),
                                ),
                              ),
                            ],
                          ),
                        ),
                        DataCell(
                          Text(
                            '₹${(p.price * qty).toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: _emeraldDark, fontSize: 14),
                          ),
                        ),
                        DataCell(
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                            onPressed: () {
                              setState(() {
                                _quantities.remove(p.id);
                              });
                            },
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOrderSummaryCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCardTitle(
            icon: Icons.receipt_long_rounded,
            title: 'Order Summary',
            subtitle: 'Cost breakdown & discount offer',
          ),
          const SizedBox(height: 20),
          _buildSummaryRow('Total Quantity', '$_totalQuantity Items'),
          const SizedBox(height: 10),
          _buildSummaryRow('Subtotal Amount', '₹${_subtotal.toStringAsFixed(2)}'),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: _cardBorder),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Offered Cost', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _darkText)),
                  Text('Optional special offer', style: TextStyle(fontSize: 11, color: _subtext)),
                ],
              ),
              SizedBox(
                width: 140,
                child: TextFormField(
                  controller: _offeredCostController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _darkText),
                  decoration: InputDecoration(
                    prefixText: '₹ ',
                    prefixStyle: const TextStyle(fontWeight: FontWeight.bold, color: _emeraldDark),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: _bgLight,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _cardBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _emeraldPrimary, width: 2),
                    ),
                  ),
                  validator: (val) {
                    if (val != null && val.isNotEmpty) {
                      final cost = double.tryParse(val);
                      if (cost == null) return 'Invalid';
                      if (cost > _subtotal) return 'Exceeds subtotal';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Offer Discount', style: TextStyle(fontSize: 13, color: _subtext)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _offerPercentage > 0 ? _emeraldLight : _bgLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_offerPercentage.toStringAsFixed(1)}% OFF',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _offerPercentage > 0 ? _emeraldDark : _subtext,
                  ),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: _cardBorder),
          ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _emeraldLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Final Payable',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _emeraldDark),
                ),
                Text(
                  '₹${_offeredCost.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _emeraldDark),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── HELPER WIDGETS ────────────────────────────────────────────────────────

  Widget _buildCardTitle({required IconData icon, required String title, required String subtitle}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _emeraldLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _emeraldDark, size: 22),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _darkText),
            ),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: _subtext),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInputField({
    TextEditingController? controller,
    String? initialValue,
    required String label,
    String? hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool readOnly = false,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _darkText),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          initialValue: initialValue,
          readOnly: readOnly,
          keyboardType: keyboardType,
          style: TextStyle(
            fontSize: 14,
            color: readOnly ? _subtext : _darkText,
            fontWeight: readOnly ? FontWeight.w500 : FontWeight.normal,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            prefixIcon: Icon(icon, color: readOnly ? _subtext : _emeraldPrimary, size: 20),
            filled: true,
            fillColor: readOnly ? const Color(0xFFF1F5F9) : _bgLight,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _emeraldPrimary, width: 1.8),
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, color: _subtext)),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _darkText)),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _clearOrder,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Clear', style: TextStyle(fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade600,
              backgroundColor: Colors.red.shade50,
              side: BorderSide(color: Colors.red.shade200),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_emeraldPrimary, _emeraldDark],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: _emeraldPrimary.withOpacity(0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: _generateAndDownloadPDF,
              icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 20),
              label: const Text(
                'Download PDF',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

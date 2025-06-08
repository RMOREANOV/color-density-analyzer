import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dynamic_height_grid_view/dynamic_height_grid_view.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:mime/mime.dart';
import 'package:pdfx/pdfx.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(debugShowCheckedModeBanner: false, color: Colors.white, title: 'Flutter Demo', home: const PdfColorAnalyzer());
  }
}

class PdfColorAnalyzer extends StatefulWidget {
  const PdfColorAnalyzer({super.key});

  @override
  PdfColorAnalyzerState createState() => PdfColorAnalyzerState();
}

class PdfColorAnalyzerState extends State<PdfColorAnalyzer> {
  List<AnalyzedDocument> analyzedDocuments = [];
  double grandTotal = 0.0;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();

    ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      _handleSharedFiles(value);
    }, onError: (err) => print("Error en mediaStream: $err"));

    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      _handleSharedFiles(value);
    });
  }

  void _handleSharedFiles(List<SharedMediaFile> files) async {
    if (files.isEmpty) return;
    setState(() => isLoading = true);

    for (final file in files) {
      try {
        if (file.mimeType == 'application/pdf') {
          final analyzed = await _analyzePdf(File(file.path));
          setState(() {
            analyzedDocuments.add(analyzed);
            _updateGrandTotal();
          });
        } else if (file.mimeType?.startsWith('image/') ?? false) {
          final analyzed = await _analyzeImage(File(file.path));
          setState(() {
            analyzedDocuments.add(analyzed);
            _updateGrandTotal();
          });
        }
      } catch (e) {
        print("Error processing file ${file.path}: $e");
      }
    }

    setState(() => isLoading = false);
  }

  void _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'gif', 'bmp'],
      allowMultiple: true,
    );

    if (result == null) return;

    setState(() => isLoading = true);

    for (final file in result.files) {
      try {
        final mimeType = lookupMimeType(file.path ?? '');
        if (mimeType == 'application/pdf') {
          final analyzed = await _analyzePdf(File(file.path!));
          setState(() {
            analyzedDocuments.add(analyzed);
            _updateGrandTotal();
          });
        } else if (mimeType?.startsWith('image/') ?? false) {
          final analyzed = await _analyzeImage(File(file.path!));
          setState(() {
            analyzedDocuments.add(analyzed);
            _updateGrandTotal();
          });
        }
      } catch (e) {
        print("Error processing file ${file.path}: $e");
      }
    }

    setState(() => isLoading = false);
  }

  void _updateGrandTotal() {
    grandTotal = 0.0;
    for (final doc in analyzedDocuments) {
      for (final page in doc.pages) {
        if (page.enabled) {
          grandTotal += page.price * page.quantity;
        }
      }
    }
  }

  Future<AnalyzedDocument> _analyzePdf(File file) async {
    final doc = await PdfDocument.openFile(file.path);
    final List<PageAnalysis> pageAnalyses = [];

    for (int i = 1; i <= doc.pagesCount; i++) {
      final page = await doc.getPage(i);
      final isLandscape = page.width > page.height;

      final pageImage = await page.render(
        width: isLandscape ? page.height : page.width,
        height: isLandscape ? page.width : page.height,
        backgroundColor: '#FFFFFF',
      );

      var image = img.decodeImage(pageImage!.bytes)!;
      if (isLandscape) {
        image = img.copyRotate(image, angle: -90);
      }

      const a4Width = 595;
      const a4Height = 842;
      final a4Image = img.Image(width: a4Width, height: a4Height);
      img.fill(a4Image, color: img.ColorRgb8(255, 255, 255));

      final scale = min(a4Width / image.width, a4Height / image.height);
      final scaledWidth = (image.width * scale).round();
      final scaledHeight = (image.height * scale).round();

      final posX = (a4Width - scaledWidth) ~/ 2;
      final posY = (a4Height - scaledHeight) ~/ 2;

      final resizedImage = img.copyResize(image, width: scaledWidth, height: scaledHeight);

      img.compositeImage(a4Image, resizedImage, dstX: posX, dstY: posY);

      final formattedImage = Uint8List.fromList(img.encodePng(a4Image));
      final analysis = await _analyzeImageBytes(formattedImage);

      pageAnalyses.add(
        PageAnalysis(
          pageNumber: i,
          density: analysis.density,
          price: analysis.price,
          image: MemoryImage(formattedImage),
          quantity: 1, // Default quantity
          isColor: true, // Default to color
        ),
      );
      await page.close();
    }

    return AnalyzedDocument(fileName: file.path.split('/').last, pages: pageAnalyses, isPdf: true);
  }

  Future<AnalyzedDocument> _analyzeImage(File file) async {
    final imageBytes = await file.readAsBytes();
    var originalImage = img.decodeImage(imageBytes)!;

    if (originalImage.width > originalImage.height) {
      originalImage = img.copyRotate(originalImage, angle: -90);
    }

    const a4Width = 595;
    const a4Height = 842;

    final a4Image = img.Image(width: a4Width, height: a4Height);
    img.fill(a4Image, color: img.ColorRgb8(255, 255, 255));

    final scale = min(a4Width / originalImage.width, a4Height / originalImage.height);

    final scaledWidth = (originalImage.width * scale).round();
    final scaledHeight = (originalImage.height * scale).round();

    final posX = (a4Width - scaledWidth) ~/ 2;
    final posY = (a4Height - scaledHeight) ~/ 2;

    final resizedImage = img.copyResize(originalImage, width: scaledWidth, height: scaledHeight);

    img.compositeImage(a4Image, resizedImage, dstX: posX, dstY: posY);

    final formattedImage = Uint8List.fromList(img.encodePng(a4Image));

    final analysis = await _analyzeImageBytes(formattedImage);

    return AnalyzedDocument(
      fileName: file.path.split('/').last,
      pages: [
        PageAnalysis(
          pageNumber: 1,
          density: analysis.density,
          price: analysis.price,
          image: MemoryImage(formattedImage),
          quantity: 1, // Default quantity
          isColor: true, // Default to color
        ),
      ],
      isPdf: false,
    );
  }

  Future<({double density, double price})> _analyzeImageBytes(Uint8List imageBytes) async {
    final image = img.decodeImage(imageBytes)!;

    int nonWhite = 0;
    const whiteThreshold = 247;
    const alphaThreshold = 0;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixelSafe(x, y);
        final r = pixel.r;
        final g = pixel.g;
        final b = pixel.b;
        final a = pixel.a;

        if ((r < whiteThreshold || g < whiteThreshold || b < whiteThreshold) && a > alphaThreshold) {
          nonWhite++;
        }
      }
    }

    final total = image.width * image.height;
    final density = (nonWhite / total) * 100;
    final price = _calculatePrice(density, true);

    return (density: density, price: price);
  }

  /*double _calculatePrice(double density, bool isColor) {
    const baseCost = 0.10;
    const laborCost = 0.10;
    const maxInkCost = 0.80;
    const maxInkCostBW = 0.50;
    const minD = 5;
    const maxD = 70;

    if (density <= minD) return baseCost + 2 * laborCost;
    if (density >= maxD) return baseCost + laborCost + (isColor ? maxInkCost : maxInkCostBW);

    final normalizedDensity = (density - minD) / (maxD - minD);
    final k = 1.5;
    final inkCost = (isColor ? maxInkCost : maxInkCostBW) * (1 - exp(-k * normalizedDensity)) / (1 - exp(-k));
    final totalPrice = baseCost + laborCost + inkCost;
    return (totalPrice * 10).ceil() / 10;
  }*/

  double _calculatePrice(double density, bool isColor) {
    const baseCost = 0.10;
    const laborCost = 0.10;
    const maxInkCost = 0.80;
    const maxInkCostBW = 0.60;
    const minD = 5;
    const maxD = 70;

    if (density <= minD) return baseCost + 2 * laborCost;
    if (density >= maxD) return baseCost + laborCost + (isColor ? maxInkCost : maxInkCostBW);

    final normalizedDensity = (density - minD) / (maxD - minD);
    final maxCost = isColor ? maxInkCost : maxInkCostBW;
    final inkCost = normalizedDensity * maxCost;
    final totalPrice = baseCost + laborCost + inkCost;
    return (totalPrice * 10).ceil() / 10;
  }

  void _updateQuantity(int docIndex, int pageIndex, int newQuantity) {
    setState(() {
      analyzedDocuments[docIndex].pages[pageIndex].quantity = newQuantity;
      _updateGrandTotal();
    });
  }

  void _togglePageEnabled(int docIndex, int pageIndex, bool enabled) {
    setState(() {
      analyzedDocuments[docIndex].pages[pageIndex].enabled = enabled;
      _updateGrandTotal();
    });
  }

  void _toggleColorMode(int docIndex, int pageIndex, bool isColor) {
    setState(() {
      final page = analyzedDocuments[docIndex].pages[pageIndex];
      page.isColor = isColor;
      page.price = _calculatePrice(page.density, isColor);
      _updateGrandTotal();
    });
  }

  void _shareCostSummary() {
    if (analyzedDocuments.isEmpty) return;
    final buffer = StringBuffer();
    buffer.writeln('📄 Print Cost Summary\n');
    for (final doc in analyzedDocuments) {
      buffer.writeln('📂 Document: ${doc.fileName}');
      for (final page in doc.pages.where((p) => p.enabled)) {
        buffer.writeln(
          '  - ${doc.isPdf ? 'Page ${page.pageNumber}' : 'Image'}: '
          //'${page.density.toStringAsFixed(2)}% density '
          '${page.isColor ? 'Color' : 'B/W'} '
          '× ${page.quantity} = S/ ${(page.price * page.quantity).toStringAsFixed(2)}',
        );
      }
      buffer.writeln('  Subtotal: S/ ${doc.totalPrice.toStringAsFixed(2)}\n');
    }
    buffer.writeln('💵 GRAND TOTAL: S/ ${grandTotal.toStringAsFixed(2)}');
    SharePlus.instance.share(ShareParams(text: buffer.toString(), subject: 'Print Cost Summary'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Color Density Analyzer 🎨')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : analyzedDocuments.isEmpty
            ? Center(
                child: ElevatedButton(onPressed: _pickFiles, child: const Text('Select PDFs or Images')),
              )
            : Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      itemCount: analyzedDocuments.length,
                      itemBuilder: (_, index) {
                        final doc = analyzedDocuments[index];
                        return DocumentResult(
                          doc: doc,
                          docIndex: index,
                          onUpdateQuantity: _updateQuantity,
                          onToggleEnabled: _togglePageEnabled,
                          onToggleColorMode: _toggleColorMode,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text("Grand Total: S/ ${grandTotal.toStringAsFixed(2)}", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton(onPressed: _pickFiles, child: const Text('Add')),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () {
                          setState(() {
                            analyzedDocuments.clear();
                            grandTotal = 0;
                          });
                        },
                        child: const Text('Reset'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(onPressed: _shareCostSummary, child: const Text('Share')),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

class PageAnalysis {
  final int pageNumber;
  final double density;
  double price;
  final ImageProvider image;
  int quantity;
  bool enabled;
  bool isColor;

  PageAnalysis({
    required this.pageNumber,
    required this.density,
    required this.price,
    required this.image,
    required this.quantity,
    this.enabled = true,
    this.isColor = true,
  });
}

class AnalyzedDocument {
  final String fileName;
  final List<PageAnalysis> pages;
  final bool isPdf;

  AnalyzedDocument({required this.fileName, required this.pages, required this.isPdf});

  double get totalPrice {
    double total = 0.0;
    for (final page in pages) {
      if (page.enabled) {
        total += page.price * page.quantity;
      }
    }
    return total;
  }
}

class DocumentResult extends StatelessWidget {
  final AnalyzedDocument doc;
  final int docIndex;
  final Function(int, int, int) onUpdateQuantity;
  final Function(int, int, bool) onToggleEnabled;
  final Function(int, int, bool) onToggleColorMode;

  const DocumentResult({
    super.key,
    required this.doc,
    required this.docIndex,
    required this.onUpdateQuantity,
    required this.onToggleEnabled,
    required this.onToggleColorMode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [Text("Results for: ${doc.fileName}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Chip(label: Text(doc.isPdf ? 'PDF' : 'Image'), backgroundColor: doc.isPdf ? Colors.blue[100] : Colors.green[100]),
            ],
          ),
          const SizedBox(height: 8),
          DynamicHeightGridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: doc.pages.length,
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            builder: (_, index) {
              final page = doc.pages[index];
              return Opacity(
                opacity: page.enabled ? 1.0 : 0.5,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: page.isColor ? Colors.blue : Colors.grey, width: page.enabled ? 2 : 1),
                            color: Colors.white,
                          ),
                          child: Stack(
                            children: [
                              Image(image: page.image, fit: BoxFit.contain),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: Checkbox(
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  value: page.enabled,
                                  onChanged: (value) {
                                    onToggleEnabled(docIndex, index, value ?? false);
                                  },
                                ),
                              ),
                              Positioned(
                                bottom: 8,
                                left: 0,
                                right: 0,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    InkWell(
                                      onTap: () => onToggleColorMode(docIndex, index, true),
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: page.isColor ? Colors.white : Colors.grey[200],
                                          shape: BoxShape.circle,
                                          border: Border.all(color: page.isColor ? Colors.blue : Colors.transparent, width: 2),
                                        ),
                                        child: Icon(Icons.color_lens, size: 20, color: page.isColor ? Colors.blue : Colors.grey),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    InkWell(
                                      onTap: () => onToggleColorMode(docIndex, index, false),
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: !page.isColor ? Colors.white : Colors.grey[200],
                                          shape: BoxShape.circle,
                                          border: Border.all(color: !page.isColor ? Colors.black : Colors.transparent, width: 2),
                                        ),
                                        child: Icon(Icons.invert_colors, size: 20, color: !page.isColor ? Colors.black : Colors.grey),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            children: [
                              Text(doc.isPdf ? "Page ${page.pageNumber}" : "Image", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                              Text("Density: ${page.density.toStringAsFixed(2)}%", style: const TextStyle(fontSize: 15)),
                              Container(
                                height: 30,
                                alignment: Alignment.center,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove, size: 18),
                                      onPressed: page.enabled
                                          ? () {
                                              if (page.quantity > 1) {
                                                onUpdateQuantity(docIndex, index, page.quantity - 1);
                                              }
                                            }
                                          : null,
                                    ),
                                    Text("${page.quantity}", style: const TextStyle(fontSize: 16, height: 1)),
                                    IconButton(
                                      icon: const Icon(Icons.add, size: 18),
                                      onPressed: page.enabled
                                          ? () {
                                              onUpdateQuantity(docIndex, index, page.quantity + 1);
                                            }
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                "Price: S/ ${(page.price * page.quantity).toStringAsFixed(2)}",
                                style: TextStyle(color: page.enabled ? Colors.green : Colors.grey, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              "Subtotal: S/ ${doc.totalPrice.toStringAsFixed(2)}",
              style: const TextStyle(color: Colors.black87, fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:pdfx/pdfx.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

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
  List<AnalyzedPdf> analyzedPdfs = [];
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
    final pdfFiles = files.where((f) => f.mimeType == 'application/pdf').toList();
    if (pdfFiles.isEmpty) return;
    setState(() => isLoading = true);
    for (final file in pdfFiles) {
      print(file.path);
      final analyzed = await _analyzePdf(File(file.path));
      setState(() {
        analyzedPdfs.add(analyzed);
        grandTotal += analyzed.totalPrice;
      });
    }
    setState(() => isLoading = false);
  }

  void _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], allowMultiple: true);
    if (result == null) return;
    final pdfFiles = result.files.where((f) => f.extension == 'pdf').toList();
    if (pdfFiles.isEmpty) return;
    setState(() => isLoading = true);
    for (final file in pdfFiles) {
      final analyzed = await _analyzePdf(File(file.path!));
      setState(() {
        analyzedPdfs.add(analyzed);
        grandTotal += analyzed.totalPrice;
      });
    }
    setState(() => isLoading = false);
  }

  Future<AnalyzedPdf> _analyzePdf(File file) async {
    final doc = await PdfDocument.openFile(file.path);
    final List<PageAnalysis> pageAnalyses = [];
    double totalPrice = 0.0;

    for (int i = 1; i <= doc.pagesCount; i++) {
      final page = await doc.getPage(i);
      final pageImage = await page.render(width: page.width, height: page.height, backgroundColor: '#FFFFFF');

      final image = img.decodeImage(pageImage!.bytes)!;

      int nonWhite = 0;
      const whiteThreshold = 252;
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
      final price = _calculatePrice(density);
      totalPrice += price;

      pageAnalyses.add(PageAnalysis(pageNumber: i, density: density, price: price, image: MemoryImage(pageImage.bytes)));
      await page.close();
    }

    return AnalyzedPdf(fileName: file.path.split('/').last, totalPrice: totalPrice, pages: pageAnalyses);
  }

  double _calculatePrice(double density) {
    const minD = 5, maxD = 70, minP = 0.30, maxP = 1.00;
    if (density <= minD) return minP;
    if (density >= maxD) return maxP;
    final x = (density - minD) / (maxD - minD);
    final k = 1.5;
    final norm = (1 - exp(-k * x)) / (1 - exp(-k));
    final price = minP + norm * (maxP - minP);
    return (price * 10).ceil() / 10;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Color Density Analyzer 🎨')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: isLoading
            ? Center(child: CircularProgressIndicator())
            : analyzedPdfs.isEmpty
            ? Center(
                child: ElevatedButton(onPressed: _pickFiles, child: Text('Select PDFs')),
              )
            : Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      itemCount: analyzedPdfs.length,
                      itemBuilder: (_, index) {
                        final pdf = analyzedPdfs[index];
                        return PdfResultCard(pdf: pdf);
                      },
                    ),
                  ),
                  SizedBox(height: 4),
                  Text("Grand Total: S/ ${grandTotal.toStringAsFixed(2)}", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton(onPressed: _pickFiles, child: Text('Add Another PDF')),
                      SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () {
                          setState(() {
                            analyzedPdfs.clear();
                            grandTotal = 0;
                          });
                        },
                        child: Text('Reset'),
                      ),
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
  final double price;
  final ImageProvider image;

  PageAnalysis({required this.pageNumber, required this.density, required this.price, required this.image});
}

class AnalyzedPdf {
  final String fileName;
  final double totalPrice;
  final List<PageAnalysis> pages;

  AnalyzedPdf({required this.fileName, required this.totalPrice, required this.pages});
}

class PdfResultCard extends StatelessWidget {
  final AnalyzedPdf pdf;

  const PdfResultCard({super.key, required this.pdf});

  @override
  Widget build(BuildContext context) {
    return Container(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Results for: ${pdf.fileName}", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            itemCount: pdf.pages.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 0.7, mainAxisSpacing: 8, crossAxisSpacing: 8),
            itemBuilder: (_, index) {
              final page = pdf.pages[index];
              return Card(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: Column(
                    children: [
                      Expanded(
                        child: Image(image: page.image, width: double.infinity),
                      ),
                      Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Column(
                          children: [
                            Text("Page ${page.pageNumber}", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                            Text("Density: ${page.density.toStringAsFixed(2)}%", style: TextStyle(fontSize: 15)),
                            Text(
                              "Price: S/ ${page.price.toStringAsFixed(2)}",
                              style: TextStyle(color: Colors.green, fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              "PDF Subtotal: S/ ${pdf.totalPrice.toStringAsFixed(2)}",
              style: TextStyle(color: Colors.black87, fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

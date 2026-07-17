import Foundation
import PDFKit
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum OpenURLHelper {
    @MainActor
    static func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    @MainActor
    static func reveal(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #else
        UIApplication.shared.open(url)
        #endif
    }
}

enum PDFAnnotationService {
    static func addFreeText(_ text: String, to url: URL) throws {
        guard let document = PDFDocument(url: url), let page = document.page(at: 0) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let pageBounds = page.bounds(for: .mediaBox)
        let bounds = CGRect(x: pageBounds.minX + 36, y: pageBounds.maxY - 120, width: min(320, pageBounds.width - 72), height: 70)
        let annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
        annotation.contents = text
        annotation.font = .systemFont(ofSize: 13)
        annotation.fontColor = .black
        annotation.color = PlatformColor.systemYellow.withAlphaComponent(0.78)
        page.addAnnotation(annotation)
        guard document.write(to: url) else { throw CocoaError(.fileWriteUnknown) }
    }
}

#if os(macOS)
private typealias PlatformColor = NSColor

struct PDFDocumentView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}
#else
private typealias PlatformColor = UIColor

struct PDFDocumentView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}
#endif

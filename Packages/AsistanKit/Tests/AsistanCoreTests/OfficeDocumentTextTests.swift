import Foundation
import Testing
@testable import AsistanCore

@Suite("OfficeDocumentText")
struct OfficeDocumentTextTests {
    private func data(_ text: String) -> Data { Data(text.utf8) }

    @Test("worksheets and slides are read in their own order")
    func parts() {
        let names = ["xl/worksheets/sheet10.xml", "xl/worksheets/sheet2.xml", "xl/worksheets/_rels/sheet2.xml.rels",
                     "xl/worksheets/sheet1.xml", "ppt/slides/slide3.xml", "ppt/slides/slide1.xml", "content.xml"]
        #expect(OfficeDocumentText.parts(of: .xlsx, in: names)
            == ["xl/worksheets/sheet1.xml", "xl/worksheets/sheet2.xml", "xl/worksheets/sheet10.xml"])
        #expect(OfficeDocumentText.parts(of: .pptx, in: names) == ["ppt/slides/slide1.xml", "ppt/slides/slide3.xml"])
        #expect(OfficeDocumentText.parts(of: .ods, in: names) == ["content.xml"])
        #expect(OfficeDocumentText.parts(of: .odp, in: []) == [])
    }

    @Test("an Excel sheet's text cells come from the shared strings, numbers stay as they are")
    func xlsx() throws {
        let shared = try OfficeDocumentText.sharedStrings(data("""
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><si><t>Kira</t></si><si><r><t>Ay</t></r><r><t>lık</t></r></si></sst>
        """))
        #expect(shared == ["Kira", "Aylık"])
        let sheet = try OfficeDocumentText.sheet(data("""
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
        <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1"><v>12500</v></c></row>
        <row r="2"><c r="A2" t="inlineStr"><is><t>Not</t></is></c><c r="B2" t="s"><v>1</v></c></row>
        <row r="3"><c r="A3"/></row>
        </sheetData></worksheet>
        """), shared: shared)
        #expect(sheet == "Kira\t12500\nNot\tAylık")
    }

    @Test("a slide's paragraphs are joined from their runs")
    func pptx() throws {
        let slide = try OfficeDocumentText.slide(data("""
        <p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
        <p:cSld><p:spTree><p:sp><p:txBody><a:p><a:r><a:t>Bütçe </a:t></a:r><a:r><a:t>2027</a:t></a:r></a:p><a:p/><a:p><a:r><a:t>Onaylandı</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>
        """))
        #expect(slide == "Bütçe 2027\nOnaylandı")
    }

    @Test("an OpenDocument spreadsheet keeps rows and drops the repeated empty cells")
    func ods() throws {
        let text = try OfficeDocumentText.openDocument(data("""
        <office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">
        <office:body><office:spreadsheet><table:table>
        <table:table-row><table:table-cell><text:p>Kira</text:p></table:table-cell><table:table-cell><text:p>12500</text:p></table:table-cell><table:table-cell table:number-columns-repeated="1000"/></table:table-row>
        </table:table></office:spreadsheet></office:body></office:document-content>
        """))
        #expect(text == "Kira\t12500")
    }

    @Test("repeated OpenDocument cells keep later columns in place")
    func odsRepeated() throws {
        let text = try OfficeDocumentText.openDocument(data("""
        <office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">
        <office:body><office:spreadsheet><table:table>
        <table:table-row><table:table-cell><text:p>Kira</text:p></table:table-cell><table:table-cell table:number-columns-repeated="2"/><table:table-cell table:number-columns-repeated="2"><text:p>5</text:p></table:table-cell><table:table-cell table:number-columns-repeated="16000"/></table:table-row>
        <table:table-row><table:table-cell><text:p>a<text:s text:c="3"/>b</text:p></table:table-cell></table:table-row>
        </table:table></office:spreadsheet></office:body></office:document-content>
        """))
        #expect(text == "Kira\t\t\t5\t5\na   b")
    }

    @Test("an OpenDocument presentation reads its paragraphs with spaces and line breaks")
    func odp() throws {
        let text = try OfficeDocumentText.openDocument(data("""
        <office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">
        <office:body><office:presentation><text:p>Yıllık<text:s/>plan</text:p><text:p>Birinci<text:line-break/>İkinci</text:p></office:presentation></office:body></office:document-content>
        """))
        #expect(text == "Yıllık plan\nBirinci\nİkinci")
    }

    @Test("refuses entity declarations and broken XML")
    func refused() {
        #expect(throws: OfficeDocumentText.ReadError.declaresEntities) {
            try OfficeDocumentText.slide(data(#"<!DOCTYPE x [<!ENTITY a "aaaa">]><x>&a;</x>"#))
        }
        #expect(throws: OfficeDocumentText.ReadError.malformed) { try OfficeDocumentText.slide(data("<a><b></a>")) }
    }
}

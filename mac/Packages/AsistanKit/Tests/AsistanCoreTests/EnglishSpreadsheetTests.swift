import Testing
@testable import AsistanCore

@Suite("English spreadsheet commands")
struct EnglishSpreadsheetTests {
    private func cell(_ address: String) -> CellReference { CellReference(address)! }

    @Test("formulas into a cell", arguments: [
        ("Put the sum of B1 and B2 into D3", "D3", "=B1+B2"),
        ("Add B1 and B2 into D3", "D3", "=B1+B2"),
        ("Put the sum of B1 to B9 in B10", "B10", "=SUM(B1:B9)"),
        ("Set D3 to B2 plus B1", "D3", "=B2+B1"),
        ("D3 equals B2 times 1.2", "D3", "=B2*1.2"),
        ("Subtract B2 from B1 into C1", "C1", "=B1-B2"),
        ("Divide B1 by B2 into C1", "C1", "=B1/B2"),
        ("Multiply B1 by C1 into D1", "D1", "=B1*C1"),
        ("Put the average of B1 through B9 in B11", "B11", "=AVERAGE(B1:B9)"),
    ])
    func formulas(text: String, target: String, formula: String) {
        #expect(SpreadsheetCommand.parse(text, language: .english) == .setFormula(target: cell(target), formula: formula))
    }

    @Test("values, reads and edits")
    func edits() {
        #expect(SpreadsheetCommand.parse("Write 1250 in C5", language: .english) == .setValue(target: cell("C5"), value: .number(1250)))
        #expect(SpreadsheetCommand.parse("Put 1,250 into C5", language: .english) == .setValue(target: cell("C5"), value: .number(1250)))
        #expect(SpreadsheetCommand.parse("Type Rent in A1", language: .english) == .setValue(target: cell("A1"), value: .text("Rent")))
        #expect(SpreadsheetCommand.parse("What's in D3?", language: .english) == .read(cell("D3")))
        #expect(SpreadsheetCommand.parse("Read B 4", language: .english) == .read(cell("B4")))
        #expect(SpreadsheetCommand.parse("Clear D3", language: .english) == .clear(cell("D3")))
        #expect(SpreadsheetCommand.parse("Copy D3 to E3", language: .english) == .copy(from: cell("D3"), to: cell("E3")))
        #expect(SpreadsheetCommand.parse("Undo", language: .english) == .undo)
        #expect(SpreadsheetCommand.parse("I'm done", language: .english) == .finish)
        #expect(SpreadsheetCommand.parse("Exit Excel mode", language: .english) == .finish)
    }

    @Test("questions are computed, not written")
    func questions() {
        #expect(SpreadsheetCommand.parse("What's the total of column B", language: .english) == .evaluate(formula: "SUM(B:B)"))
        #expect(SpreadsheetCommand.parse("What is the sum of B1 to B9", language: .english) == .evaluate(formula: "SUM(B1:B9)"))
        #expect(SpreadsheetCommand.parse("What's the largest value in C2 through C11", language: .english)
            == .evaluate(formula: "MAX(C2:C11)"))
    }

    @Test("other requests are not spreadsheet commands")
    func ignored() {
        #expect(SpreadsheetCommand.parse("Open Safari", language: .english) == nil)
        #expect(SpreadsheetCommand.parse("Add milk to my list", language: .english) == nil)
        #expect(SpreadsheetCommand.mentionsCells("Calculate the tax in D2", language: .english))
        #expect(!SpreadsheetCommand.mentionsCells("What's the weather", language: .english))
    }
}

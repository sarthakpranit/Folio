//
// LibraryViewMode.swift
// Folio
//
// Defines the display modes for the library view.
// Grid mode shows book covers in a visual grid (default).
// Table mode provides a spreadsheet-like list for large libraries.
//
// Design Rationale:
// - Grid: Visual browsing, cover-centric, best for smaller collections
// - Table: Information-dense, sortable columns, best for large collections
//

import Foundation

enum LibraryViewMode: String, CaseIterable {
    case grid = "Grid"
    case table = "Table"

    var icon: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .table: return "list.bullet"
        }
    }
}

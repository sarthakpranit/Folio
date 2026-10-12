//
//  Book+FilePath.swift
//  Folio
//
//  `Book` stores its file location as a plain path string (`filePath`) rather
//  than a Core Data `URI` attribute. `URI` attributes reject string predicates
//  (`==[c]`, `CONTAINS`, `BEGINSWITH`) — the class of runtime crash behind #9 —
//  so nothing querying a book by path is one careless predicate away from a
//  fault. Callers still work in terms of `URL`; this bridge is the only place
//  the string form is read or written (#137).
//

import CoreData
import Foundation

extension Book {
    /// The book's file as a `URL`, backed by the stored `filePath` string.
    /// `nil` when the book has no known location (an orphan awaiting review).
    ///
    /// `nonisolated` to match the `@NSManaged` accessor it replaces — Core Data
    /// confines access through the managed object's context, not actor isolation,
    /// and the import path writes this from a background context.
    nonisolated var fileURL: URL? {
        get { filePath.map { URL(fileURLWithPath: $0) } }
        set { filePath = newValue?.path }
    }
}

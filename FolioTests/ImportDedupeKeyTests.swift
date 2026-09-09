//
//  ImportDedupeKeyTests.swift
//  FolioTests
//
//  When bulk import moved onto a background context (#43), inserts are saved one
//  chunk at a time instead of one file at a time. The old per-file save meant a
//  book listed twice in a single drag was already persisted by the time the
//  second copy was looked up, so `findDuplicate` caught it. The chunked save
//  loses that, so `ImportService` now carries an explicit set of normalised keys
//  to collapse batch-local duplicates.
//
//  These tests pin that key derivation: two entries that denote the same book
//  MUST share a key (or the library gets two rows for one book), and two
//  genuinely different books MUST NOT collide (or the second silently vanishes).
//

import Testing
@testable import Folio

@Suite("Import batch-local dedupe keys")
struct ImportDedupeKeyTests {

    @Test("Same filename in different folders collides (one drag, two copies)")
    func sameFilenameCollides() {
        let a = ImportService.dedupeKeys(filename: "1984 - George Orwell.epub",
                                         sortTitle: "1984", author: "George Orwell")
        let b = ImportService.dedupeKeys(filename: "1984 - George Orwell.epub",
                                         sortTitle: "1984", author: "George Orwell")
        #expect(!Set(a).isDisjoint(with: Set(b)))
    }

    @Test("Same title + author with different filenames still collides")
    func sameTitleAuthorCollides() {
        let a = ImportService.dedupeKeys(filename: "dune.epub",
                                         sortTitle: "dune", author: "Frank Herbert")
        let b = ImportService.dedupeKeys(filename: "Dune (retail).epub",
                                         sortTitle: "dune", author: "F. Herbert")
        // Both reduce to the author's last name, so the title+author key matches.
        #expect(!Set(a).isDisjoint(with: Set(b)))
    }

    @Test("Different books do not collide")
    func differentBooksDoNotCollide() {
        let hobbit = ImportService.dedupeKeys(filename: "The Hobbit - J.R.R. Tolkien.epub",
                                              sortTitle: "hobbit", author: "J.R.R. Tolkien")
        let dune = ImportService.dedupeKeys(filename: "Dune - Frank Herbert.epub",
                                            sortTitle: "dune", author: "Frank Herbert")
        #expect(Set(hobbit).isDisjoint(with: Set(dune)))
    }

    @Test("Title-only key is used when there is no author, and still collides")
    func titleOnlyKey() {
        let a = ImportService.dedupeKeys(filename: "poems-a.epub", sortTitle: "collected poems", author: nil)
        let b = ImportService.dedupeKeys(filename: "poems-b.epub", sortTitle: "Collected Poems", author: "")
        #expect(!Set(a).isDisjoint(with: Set(b)))
    }
}

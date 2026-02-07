// URL+Extensions.swift
// URL utility extensions for file operations

import Foundation

public extension URL {
    /// Check if URL points to an ebook file
    var isEbookFile: Bool {
        EbookFormat(url: self) != nil
    }

    /// Get the ebook format if applicable
    var ebookFormat: EbookFormat? {
        EbookFormat(url: self)
    }

    /// Get file size in bytes
    var fileSize: Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: self.path),
              let size = attributes[.size] as? Int64 else {
            return nil
        }
        return size
    }

    /// Get file creation date
    var creationDate: Date? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: self.path),
              let date = attributes[.creationDate] as? Date else {
            return nil
        }
        return date
    }

    /// Get file modification date
    var modificationDate: Date? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: self.path),
              let date = attributes[.modificationDate] as? Date else {
            return nil
        }
        return date
    }

    /// Check if file exists
    var fileExists: Bool {
        FileManager.default.fileExists(atPath: self.path)
    }

    /// Check if URL is a directory
    var isDirectory: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: self.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Get human-readable file size
    var formattedFileSize: String {
        guard let size = fileSize else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// Get unique filename if file already exists at destination
    func uniqueURL(in directory: URL) -> URL {
        let filename = self.deletingPathExtension().lastPathComponent
        let ext = self.pathExtension
        var newURL = directory.appendingPathComponent(self.lastPathComponent)
        var counter = 1

        while newURL.fileExists {
            let newFilename = "\(filename) (\(counter)).\(ext)"
            newURL = directory.appendingPathComponent(newFilename)
            counter += 1
        }

        return newURL
    }
}

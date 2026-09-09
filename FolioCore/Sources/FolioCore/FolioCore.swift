// FolioCore.swift
// Main module file - exports all public types

import Foundation
import OSLog

/// FolioCore version
public let FolioCoreVersion = "1.0.0"

/// FolioCore build date
public let FolioCoreBuildDate = "2025-02-08"

/// Shared logger for FolioCore. One subsystem (`com.folio`) across the app and
/// this package; components that want their own bucket create a
/// `Logger(subsystem: "com.folio", category: ...)` of their own.
let logger = Logger(subsystem: "com.folio", category: "FolioCore")

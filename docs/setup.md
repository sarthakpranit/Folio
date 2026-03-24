# Setup

This document consolidates Xcode setup guidance.

## macOS App Setup (Summary)
- Create macOS App target (SwiftUI + Core Data)
- Add local FolioCore package dependency
- Set deployment target to macOS 13+
- Enable App Sandbox with inbound/outbound network access and user-selected file access

## Core Data
- Use `Folio.xcdatamodeld` for entities
- Configure CloudKit later when entitlements are ready

## Build
- Build and run in Xcode (My Mac)

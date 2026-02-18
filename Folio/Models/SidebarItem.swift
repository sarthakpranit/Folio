//
// SidebarItem.swift
// Folio
//
// Represents selectable items in the sidebar navigation.
// Follows Apple HIG sidebar patterns with smart filters,
// entity-based navigation, and device sections.
//
// Navigation Structure:
// - Smart Filters: allBooks, recentlyAdded, recentlyOpened
// - Browse By: authors, series, tags, format(String)
// - Entity Detail: author(Author), singleSeries(Series), tag(Tag)
// - Kindle: kindleDevices, kindleDevice(KindleDevice)
//

import Foundation

enum SidebarItem: Hashable {
    // Smart filters
    case allBooks
    case recentlyAdded
    case recentlyOpened

    // Browse categories
    case authors
    case series
    case tags
    case format(String)

    // Entity-specific views
    case author(Author)
    case singleSeries(Series)
    case tag(Tag)

    // Kindle devices
    case kindleDevice(KindleDevice)
    case kindleDevices
}

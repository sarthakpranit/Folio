//
//  FolioApp.swift
//  Folio
//
//  Created by Sarthak Pranit on 14/12/2025.
//

import SwiftUI
import CoreData

@main
struct FolioApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}

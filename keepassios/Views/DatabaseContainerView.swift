import KPAppState
import KPModel
import KPSession
import SwiftUI

/// Shows the unlock form or the database, depending on the session.
struct DatabaseContainerView: View {
    @Environment(AppModel.self) private var model
    let reference: DatabaseReference

    var body: some View {
        let session = model.session(for: reference)
        SwiftUI.Group {
            if session.state == .unlocked, let database = session.database {
                GroupView(session: session, databaseID: reference.id, groupID: database.root.id, isRoot: true)
            } else {
                UnlockView(session: session, reference: reference)
            }
        }
        .onChange(of: session.state) { _, state in
            if state == .unlocked {
                Task { await model.markOpened(reference.id) }
            }
        }
        .onChange(of: session.hasUnsavedChanges) { _, unsaved in
            // Every edit is saved right away, as in other KeePass apps, so
            // locking or leaving never loses work.
            if unsaved {
                Task { await model.save(session) }
            }
        }
    }
}

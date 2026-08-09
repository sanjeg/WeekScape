//
//  PlanTransfer.swift
//  Weekend Planner
//
//  Lightweight Transferable payload used for drag-and-drop. We only carry the
//  plan's identifier and let the receiving view resolve the live model from the
//  SwiftData context. A string proxy representation is used so drags work
//  without requiring a custom UTI declaration in Info.plist.
//

import CoreTransferable
import Foundation

struct PlanTransfer: Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(
            exporting: { $0.id.uuidString },
            importing: { string in
                guard let uuid = UUID(uuidString: string) else {
                    throw CocoaError(.coderInvalidValue)
                }
                return PlanTransfer(id: uuid)
            }
        )
    }
}

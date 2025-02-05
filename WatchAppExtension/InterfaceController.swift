//
//  InterfaceController.swift
//  WatchApp Extension
//
//  Created by Robert Trencheny on 9/24/18.
//  Copyright © 2018 Robbie Trencheny. All rights reserved.
//

import Foundation
import WatchKit
import Iconic
import EMTLoadingIndicator
import RealmSwift
import Communicator
import Shared

class InterfaceController: WKInterfaceController {
    @IBOutlet weak var tableView: WKInterfaceTable!
    @IBOutlet weak var noActionsLabel: WKInterfaceLabel!

    var actions: Results<Action>?

    override func awake(withContext context: Any?) {
        super.awake(withContext: context)

        Iconic.registerMaterialDesignIcons()

        self.setupTable()
    }

    override func willActivate() {
        // This method is called when watch view controller is about to be visible to user
        super.willActivate()
    }

    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible
        super.didDeactivate()
    }

    func setupTable() {
        let realm = Realm.live()

        let actions = realm.objects(Action.self).sorted(byKeyPath: "Position")

        self.tableView.setNumberOfRows(actions.count, withRowType: "actionRowType")

        self.noActionsLabel.setText(L10n.Watch.Labels.noAction)
        self.noActionsLabel.setHidden(actions.count > 0)

        for (i, action) in actions.enumerated() {
            if let row = self.tableView.rowController(at: i) as? ActionRowType {
                Current.Log.verbose("Setup row \(i) with action \(action)")
                row.group.setBackgroundColor(UIColor(hex: action.BackgroundColor))
                row.indicator = EMTLoadingIndicator(interfaceController: self, interfaceImage: row.image,
                                                    width: 24, height: 24, style: .dot)
                row.icon = MaterialDesignIcons.init(named: action.IconName)
                let iconColor = UIColor(hex: action.IconColor)
                row.image.setImage(row.icon.image(ofSize: CGSize(width: 24, height: 24), color: iconColor))
                row.image.setAlpha(1)
                row.label.setText(action.Text)
                row.label.setTextColor(UIColor(hex: action.TextColor))
            }
        }

        self.actions = actions

    }

    override func table(_ table: WKInterfaceTable, didSelectRowAt rowIndex: Int) {
        let selectedAction = self.actions![rowIndex]

        Current.Log.verbose("Selected action row at index \(rowIndex), \(selectedAction)")

        guard let row = self.tableView.rowController(at: rowIndex) as? ActionRowType else {
            Current.Log.warning("Row at \(rowIndex) is not ActionRowType")
            return
        }

        row.indicator?.prepareImagesForWait()
        row.indicator?.showWait()

        if Communicator.shared.currentReachability == .immediateMessaging {
            Current.Log.verbose("Signaling action pressed via phone")
            let actionMessage = ImmediateMessage(identifier: "ActionRowPressed",
                                                 content: ["ActionID": selectedAction.ID,
                                                           "ActionName": selectedAction.Name],
                                                 replyHandler: { replyDict in
                                                    Current.Log.verbose("Received reply dictionary \(replyDict)")

                                                    self.handleActionSuccess(row)
            }, errorHandler: { err in
                Current.Log.error("Received error when sending immediate message \(err)")

                self.handleActionFailure(row)
            })

            Current.Log.verbose("Sending ActionRowPressed message \(actionMessage)")

            do {
                try Communicator.shared.send(immediateMessage: actionMessage)
                self.handleActionSuccess(row)
            } catch let error {
                Current.Log.error("Action notification send failed: \(error)")

                self.handleActionFailure(row)
            }
        } else if Communicator.shared.currentReachability == .notReachable { // Phone isn't connected
            Current.Log.verbose("Signaling action pressed via watch")
            HomeAssistantAPI.authenticatedAPIPromise.then { api in
                api.HandleAction(actionID: selectedAction.ID, actionName: selectedAction.Name, source: .Watch)
            }.done { _ in
                self.handleActionSuccess(row)
            }.catch { err -> Void in
                Current.Log.error("Error during action event fire: \(err)")
                self.handleActionFailure(row)
            }
        }
    }

    func handleActionSuccess(_ row: ActionRowType) {
        WKInterfaceDevice.current().play(.success)

        row.image.stopAnimating()

        row.image.setImage(row.icon.image(ofSize: CGSize(width: 24, height: 24), color: .white))
    }

    func handleActionFailure(_ row: ActionRowType) {
        WKInterfaceDevice.current().play(.failure)

        row.image.stopAnimating()

        row.image.setImage(row.icon.image(ofSize: CGSize(width: 24, height: 24), color: .white))
    }
}
